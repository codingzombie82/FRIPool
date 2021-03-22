pragma solidity 0.5.10;
import "../node_modules/@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "../node_modules/@openzeppelin/contracts/token/ERC20/ERC20Detailed.sol";
import "./Ownable.sol";

contract Dream is ERC20, Ownable, ERC20Detailed {

    string private constant _name = "Food Research Institute for Mankind";
    string private constant _symbol = "FRI";
    uint8 private constant _decimals = 18;
    uint256 private constant _totalSupply = 5000000000;

    event Freeze(address target, bool frozen);
    mapping (address => bool) private frozenAccount;

    constructor() ERC20Detailed(_name, _symbol, _decimals) onlyOwner public {
        uint256 INITIAL_SUPPLY = _totalSupply * (10 ** uint(_decimals));
        _mint(owner(), INITIAL_SUPPLY);
    }

    function burn(uint256 amount) public onlyOwner {
        _burn(msg.sender, amount);
    }

    /* This generates a public event on the blockchain that will notify clients */
    function freeze(address _address, bool _state) public onlyOwner returns (bool) {
		frozenAccount[_address] = _state;

        emit Freeze(_address, _state);
		return true;
	}

    function transfer(address _to, uint256 _value) public returns (bool success) {
		require(!frozenAccount[msg.sender],"The wallet of sender is frozen");

		return super.transfer(_to, _value);
    }

    function transferFrom(address _from, address _to, uint256 _value) public returns (bool success) {
		require(!frozenAccount[_from],"The wallet of sender is frozen");

        return super.transferFrom(_from, _to, _value);
	}
}
