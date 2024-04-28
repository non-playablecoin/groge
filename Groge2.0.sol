
contract ERC420 is Ownable {
    using Arrays for uint256[];
    using Arrays for address[];
    using SafeMath for uint256;

    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;

    mapping(uint256 => mapping(address => uint256)) private _nft_balances;
    mapping(address => mapping(address => bool)) private _operatorApprovals;

    string private _name;
    string private _symbol;
    uint256 private _totalSupply;
    uint8 private constant _decimals = 18;
    uint256 public immutable _nft_count;

    mapping(address => bool) private _allowList;

    // Events ERC20

    event Transfer(address indexed from, address indexed to, uint256 value);

    event Approval(
        address indexed owner,
        address indexed spender,
        uint256 value
    );

    // Events ERC1155
    event TransferSingle(
        address indexed operator,
        address indexed from,
        address indexed to,
        uint256 id,
        uint256 value
    );

    event TransferBatch(
        address indexed operator,
        address indexed from,
        address indexed to,
        uint256[] ids,
        uint256[] values
    );

    event ApprovalForAll(
        address indexed account,
        address indexed operator,
        bool approved
    );

    event URI(string value, uint256 indexed id);

    event AllowListChange(
        address indexed target,
        bool approved
    );

    // Errors

    error ERC20InsufficientBalance(
        address sender,
        uint256 balance,
        uint256 needed
    );
    error ERC1155InsufficientBalance(
        address sender,
        uint256 balance,
        uint256 needed,
        uint256 tokenId
    );

    error InvalidSender(address sender);
    error InvalidReceiver(address receiver);
    error InsufficientAllowance(
        address spender,
        uint256 allowance,
        uint256 needed
    );
    error MissingApprovalForAll(address operator, address owner);
    error InvalidOperator(address operator);
    error InvalidApprover(address approver);
    error InvalidSpender(address spender);
    error InvalidArrayLength(uint256 idsLength, uint256 valuesLength);

    constructor(
        string memory name_,
        string memory symbol_,
        uint256 supply_,
        uint256 nft_count_
    ) Ownable(msg.sender) {
        _name = name_;
        _symbol = symbol_;
        _nft_count = nft_count_;
        _allowList[msg.sender] = true;
        _mint(msg.sender, supply_ * 10**_decimals);
    }

    function isInAllowlist(address target) public view returns (bool) {
        return _allowList[target];
    }

    function setAllowList(address target, bool state) public onlyOwner {
        require(
            _allowList[target] != state,
            "Assigning the same state is not allowed"
        );
        _allowList[target] = state;
        uint256 balance = _balances[target];
        if (state) {
            uint256 tokens_to_burn = balance / 10**_decimals;
            if (tokens_to_burn > 0) {
                _nft_burn(target, 0, tokens_to_burn);
            }
        } else {
            uint256 tokens_to_mint = balance / 10**_decimals;
            if (tokens_to_mint > 0) {
                _nft_mint(target, 0, tokens_to_mint);
            }
        }
        emit AllowListChange(target, state);
    }

    // ERC 1155

    function balanceOf(address account, uint256 id)
        public
        view
        returns (uint256)
    {
        require(id < _nft_count, "invalid token id");
        return _nft_balances[id][account];
    }

    function balanceOfBatch(address[] calldata accounts, uint256[] calldata ids)
        external
        view
        returns (uint256[] memory)
    {
        if (accounts.length != ids.length) {
            revert InvalidArrayLength(ids.length, accounts.length);
        }

        uint256[] memory batchBalances = new uint256[](accounts.length);

        for (uint256 i = 0; i < accounts.length; ++i) {
            batchBalances[i] = balanceOf(accounts[i], ids[i]);
        }

        return batchBalances;
    }

    function isApprovedForAll(address account, address operator)
        public
        view
        returns (bool)
    {
        return _operatorApprovals[account][operator];
    }

    function safeTransferFrom(
        address from,
        address to,
        uint256 id,
        uint256 value,
        bytes calldata
    ) external {
        address sender = msg.sender;
        if (from != sender && !isApprovedForAll(from, sender)) {
            revert MissingApprovalForAll(sender, from);
        }
        _safeTransferFrom(from, to, id, value);
    }

    function safeBatchTransferFrom(
        address from,
        address to,
        uint256[] calldata ids,
        uint256[] calldata values,
        bytes calldata
    ) external {
        address sender = msg.sender;
        if (from != sender && !isApprovedForAll(from, sender)) {
            revert MissingApprovalForAll(sender, from);
        }
        _safeBatchTransferFrom(from, to, ids, values);
    }

    function setApprovalForAll(address operator, bool approved) external {
        if (operator == address(0)) {
            revert InvalidOperator(address(0));
        }
        address owner = msg.sender;
        _operatorApprovals[owner][operator] = approved;
        emit ApprovalForAll(owner, operator, approved);
    }

    function _nft_update(
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory values
    ) internal virtual {
        if (ids.length != values.length) {
            revert InvalidArrayLength(ids.length, values.length);
        }

        address operator = msg.sender;

        for (uint256 i = 0; i < ids.length; ++i) {
            uint256 id = ids.unsafeMemoryAccess(i);
            uint256 value = values.unsafeMemoryAccess(i);

            if (from != address(0)) {
                uint256 fromBalance = _nft_balances[id][from];
                if (fromBalance < value) {
                    revert ERC1155InsufficientBalance(
                        from,
                        fromBalance,
                        value,
                        id
                    );
                }
                unchecked {
                    // Overflow not possible: value <= fromBalance
                    _nft_balances[id][from] = fromBalance - value;
                }
            }

            if (to != address(0)) {
                _nft_balances[id][to] += value;
            }
        }

        if (ids.length == 1) {
            uint256 id = ids.unsafeMemoryAccess(0);
            uint256 value = values.unsafeMemoryAccess(0);
            emit TransferSingle(operator, from, to, id, value);
        } else {
            emit TransferBatch(operator, from, to, ids, values);
        }
    }

    function _nft_burn(
        address from,
        uint256 id,
        uint256 value
    ) internal {
        if (from == address(0)) {
            revert IERC1155Errors.ERC1155InvalidSender(address(0));
        }
        (uint256[] memory ids, uint256[] memory values) = _asSingletonArrays(
            id,
            value
        );
        _nft_update(from, address(0), ids, values);
    }

    function _nft_mint(
        address to,
        uint256 id,
        uint256 value
    ) internal {
        if (to == address(0)) {
            revert IERC1155Errors.ERC1155InvalidReceiver(address(0));
        }
        (uint256[] memory ids, uint256[] memory values) = _asSingletonArrays(
            id,
            value
        );
        _nft_update(address(0), to, ids, values);
    }

    function _safeTransferFrom(
        address from,
        address to,
        uint256 id,
        uint256 value
    ) internal {
        if (to == address(0)) {
            revert InvalidReceiver(address(0));
        }
        if (from == address(0)) {
            revert InvalidSender(address(0));
        }
        (uint256[] memory ids, uint256[] memory values) = _asSingletonArrays(
            id,
            value
        );
        _update(from, to, value * 10**_decimals);
        if (!isInAllowlist(from)) {
            _nft_update(from, address(0), ids, values);
        }
        if (!isInAllowlist(to)) {
            _nft_mint(to, 0, value);
        }
    }

    function _safeBatchTransferFrom(
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory values
    ) internal {
        if (to == address(0)) {
            revert InvalidReceiver(address(0));
        }
        if (from == address(0)) {
            revert InvalidSender(address(0));
        }
        uint256 value;
        for (uint256 i = 0; i < ids.length; i++) {
            value += values[i];
        }
        _update(from, to, value * 10**_decimals);
        if (!isInAllowlist(from)) {
            _nft_update(from, address(0), ids, values);
        }
        if (!isInAllowlist(to)) {
            _nft_mint(to, 0, value);
        }
    }

    function _asSingletonArrays(uint256 element1, uint256 element2)
        private
        pure
        returns (uint256[] memory array1, uint256[] memory array2)
    {
        assembly ("memory-safe") {
            array1 := mload(0x40)
            mstore(array1, 1)
            mstore(add(array1, 0x20), element1)
            array2 := add(array1, 0x40)
            mstore(array2, 1)
            mstore(add(array2, 0x20), element2)
            mstore(0x40, add(array2, 0x40))
        }
    }

    // ERC 20 methods

    function name() public view virtual returns (string memory) {
        return _name;
    }

    function symbol() public view virtual returns (string memory) {
        return _symbol;
    }

    function decimals() public view virtual returns (uint8) {
        return _decimals;
    }

    function totalSupply() public view virtual returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) external view returns (uint256) {
        return _balances[account];
    }

    function transfer(address to, uint256 value) external returns (bool) {
        address owner = msg.sender;
        _transfer(owner, to, value);
        return true;
    }

    function allowance(address owner, address spender)
        public
        view
        virtual
        returns (uint256)
    {
        return _allowances[owner][spender];
    }

    function approve(address spender, uint256 value) external returns (bool) {
        address owner = msg.sender;
        _approve(owner, spender, value);
        return true;
    }

    function increaseAllowance(address _spender, uint256 _addedValue) public returns (bool) {
        _approve(msg.sender, _spender, _allowances[msg.sender][_spender].add(_addedValue));
        return true;
    }

    function decreaseAllowance(address _spender, uint256 _subtractedValue) public returns (bool) {
        uint256 currentAllowance = _allowances[msg.sender][_spender];
        require(currentAllowance >= _subtractedValue, "DECREASED_ALLOWANCE_BELOW_ZERO");
        _approve(msg.sender, _spender, currentAllowance.sub(_subtractedValue));
        return true;
    }

    function transferFrom(
        address from,
        address to,
        uint256 value
    ) external returns (bool) {
        address spender = msg.sender;
        _spendAllowance(from, spender, value);
        _transfer(from, to, value);
        return true;
    }

    function _transfer(
        address from,
        address to,
        uint256 value
    ) internal {
        if (from == address(0)) {
            revert InvalidSender(address(0));
        }
        if (to == address(0)) {
            revert InvalidReceiver(address(0));
        }

        uint256 balanceBeforeSender = _balances[from];
        uint256 balanceBeforeReceiver = _balances[to];

        _update(from, to, value);

        if (!isInAllowlist(from)) {
            uint256 tokens_to_burn = (balanceBeforeSender / 10**_decimals) -
                (_balances[from] / 10**_decimals);
            _nft_burn(from, 0, tokens_to_burn);
        }

        if (!isInAllowlist(to)) {
            uint256 tokens_to_mint = (_balances[to] / 10**_decimals) -
                (balanceBeforeReceiver / 10**_decimals);
            _nft_mint(to, 0, tokens_to_mint);
        }
    }

    function _update(
        address from,
        address to,
        uint256 value
    ) internal virtual {
        if (from == address(0)) {
            _totalSupply += value;
        } else {
            uint256 fromBalance = _balances[from];
            if (fromBalance < value) {
                revert ERC20InsufficientBalance(from, fromBalance, value);
            }
            unchecked {
                _balances[from] = fromBalance - value;
            }
        }

        if (to == address(0)) {
            unchecked {
                _totalSupply -= value;
            }
        } else {
            unchecked {
                _balances[to] += value;
            }
        }

        emit Transfer(from, to, value);
    }

    function _mint(address account, uint256 value) internal {
        if (account == address(0)) {
            revert InvalidReceiver(address(0));
        }
        _update(address(0), account, value);
    }

    function burn(uint256 value) external {
        address owner = msg.sender;
        if (owner == address(0)) {
            revert InvalidSender(address(0));
        }
        if (!isInAllowlist(owner)) {
            revert InvalidSender(owner);
        }
        _burn(owner, value);
    }

    function _burn(address account, uint256 value) internal {
        if (account == address(0)) {
            revert InvalidSender(address(0));
        }
        _update(account, address(0), value);
    }

    function _approve(
        address owner,
        address spender,
        uint256 value
    ) internal {
        _approve(owner, spender, value, true);
    }

    function _approve(
        address owner,
        address spender,
        uint256 value,
        bool emitEvent
    ) internal virtual {
        if (owner == address(0)) {
            revert InvalidApprover(address(0));
        }
        if (spender == address(0)) {
            revert InvalidSpender(address(0));
        }
        _allowances[owner][spender] = value;
        if (emitEvent) {
            emit Approval(owner, spender, value);
        }
    }

    function _spendAllowance(
        address owner,
        address spender,
        uint256 value
    ) internal virtual {
        uint256 currentAllowance = allowance(owner, spender);
        if (currentAllowance != type(uint256).max) {
            if (currentAllowance < value) {
                revert InsufficientAllowance(spender, currentAllowance, value);
            }
            unchecked {
                _approve(owner, spender, currentAllowance - value, false);
            }
        }
    }
}

pragma solidity ^0.8.23;

contract Groge is ERC420 {
    string public baseURI;

    constructor(
        string memory name_,
        string memory symbol_,
        string memory _baseURI
    ) ERC420(name_, symbol_, 700000000, 1) {
        baseURI = _baseURI;
    }

    function setURI(string memory newURI) public onlyOwner {
        baseURI = newURI;
    }

    function uri(uint256 _tokenId) public view returns (string memory) {
        return
            string(
                abi.encodePacked(
                    baseURI,
                    "/",
                    Strings.toString(_tokenId),
                    ".json"
                )
            );
    }
}
