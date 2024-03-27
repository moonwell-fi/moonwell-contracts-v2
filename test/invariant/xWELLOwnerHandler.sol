pragma solidity 0.8.19;

import {EnumerableSet} from "@openzeppelin-contracts/contracts/utils/structs/EnumerableSet.sol";

import "forge-std/Test.sol";

import {xWELL} from "@protocol/xWELL/xWELL.sol";
import {MockERC20} from "@test/mock/MockERC20.sol";
import {XERC20Lockbox} from "@protocol/xWELL/XERC20Lockbox.sol";

contract xWELLOwnerHandlerInvariant is Test {
    using EnumerableSet for EnumerableSet.AddressSet;

    mapping(address => EnumerableSet.AddressSet) internal _users;

    /// list of all addresses that have delegated to a user
    /// key is user --> value is list of delegators
    mapping(address => EnumerableSet.AddressSet) internal _usersDelegators;

    uint256 public constant MAX_USERS = 50;

    address[] public users;

    mapping(address => uint256) public userBalances;

    xWELL public immutable xwell;
    MockERC20 public immutable well;

    XERC20Lockbox public xerc20Lockbox;

    uint256 public totalSupply;

    address creator;

    constructor(address _xWELL, address _well, address lockbox) {
        creator = msg.sender;

        xwell = xWELL(_xWELL);
        well = MockERC20(_well);
        xerc20Lockbox = XERC20Lockbox(lockbox);

        for (uint160 i = 0; i < MAX_USERS; i++) {
            address user = address(i + 100);
            users.push(user);
        }
    }

    /// not callable by the fuzzing engine
    function sync() external {
        require(msg.sender == creator, "not creator");

        totalSupply = xwell.totalSupply();

        for (uint160 i = 0; i < MAX_USERS; i++) {
            address user = address(i + 100);
            /// sync balances mapping
            userBalances[user] = xwell.balanceOf(user);
        }
    }

    function getUsers() public view returns (address[] memory) {
        return users;
    }

    function getUserDelegators(
        uint8 user
    ) external view returns (address[] memory) {
        return _usersDelegators[users[user]].values();
    }

    function getUserDelegators(
        address user
    ) external view returns (address[] memory) {
        return _usersDelegators[user].values();
    }

    function warp(uint16 amount) external {
        amount = uint16(_bound(amount, 0, type(uint32).max));
        if (uint256(amount) < type(uint32).max) {
            vm.warp(block.timestamp + amount);
        }
    }

    /// ----------------------------------------------------------------------------------
    /// ----------------------------------------------------------------------------------
    /// ----------- Buffer Cap and Rate Limit Changes for the bridge contract ------------
    /// ----------------------------------------------------------------------------------
    /// ----------------------------------------------------------------------------------

    /// rate limit changes
    function setRateLimitPerSecond(bool limiter, uint128 rateLimit) external {
        rateLimit = uint128(_bound(rateLimit, 0, type(uint128).max));

        address toLimit = limiter == true ? address(this) : address(xwell);

        vm.prank(xwell.owner());
        xwell.setRateLimitPerSecond(toLimit, rateLimit);
    }

    /// buffer cap changes
    function setBufferCap(bool limiter, uint112 bufferCap) external {
        bufferCap = uint112(_bound(bufferCap, 0, type(uint112).max));

        address toLimit = limiter == true ? address(this) : address(xwell);

        vm.prank(xwell.owner());
        xwell.setBufferCap(toLimit, bufferCap);
    }

    /// transfers

    function transfer(uint8 _to, uint8 _from, uint112 amount) external {
        address to = users[(_bound(_to, 0, users.length - 1))];
        address from = users[(_bound(_from, 0, users.length - 1))];

        amount = uint112(_bound(amount, 1, userBalances[from]));

        vm.prank(from);
        xwell.transfer(to, amount);

        unchecked {
            userBalances[from] -= amount;
            userBalances[to] += amount;
        }
    }

    function transferFrom(
        uint8 _to,
        uint8 _from,
        uint8 _owner,
        uint112 amount
    ) external {
        address to = users[(_bound(_to, 0, users.length - 1))];
        address from = users[(_bound(_from, 0, users.length - 1))];
        address owner = users[(_bound(_owner, 0, users.length - 1))];

        amount = uint112(_bound(amount, 1, userBalances[owner]));

        vm.prank(owner);
        xwell.approve(from, amount);

        vm.prank(from);
        xwell.transferFrom(owner, to, amount);

        unchecked {
            userBalances[owner] -= amount;
            userBalances[to] += amount;
        }
    }

    /// @delegation - test relationship betweeen delegatee and delegator

    /// delegate - reverts only if from has delegated to to
    function delegate(uint8 to, uint8 from) external {
        address delegator = users[(_bound(from, 0, users.length - 1))];
        address delegatee = users[(_bound(to, 0, users.length - 1))];

        /// do a check if the delegator has already delegated, if so, remove them
        address existingDelegated = xwell.delegates(delegator);
        if (existingDelegated != address(0)) {
            require(
                _usersDelegators[existingDelegated].remove(delegator),
                "did not properly undelegate"
            );
        }

        require(
            _usersDelegators[delegatee].add(delegator),
            "already delegated"
        );

        vm.prank(delegator);
        xwell.delegate(delegatee);
    }

    /// undelegate
    function undelegate(uint8 from) external {
        address delegator = users[(_bound(from, 0, users.length - 1))];
        address delegatee = xwell.delegates(delegator);

        require(
            _usersDelegators[delegatee].remove(delegator),
            "already delegated"
        );

        vm.prank(delegator);
        xwell.delegate(address(0));
    }

    /// ------- lockbox -------
    /// depositTo

    function depositTo(uint8 _to, uint112 amount) external {
        address to = users[(_bound(_to, 0, users.length - 1))];

        /// at minimum mint 1 xWELL
        amount = uint112(
            _bound(amount, 1, xwell.maxSupply() - xwell.totalSupply())
        );

        well.mint(address(this), amount);
        well.approve(address(xerc20Lockbox), amount);

        xerc20Lockbox.depositTo(to, amount);

        unchecked {
            userBalances[to] += amount;
            totalSupply += amount;
        }
    }

    /// withdrawTo

    function withdrawTo(uint8 _to, uint112 amount) external {
        address to = users[(_bound(_to, 0, users.length - 1))];

        uint256 amtCeiling = xwell.balanceOf(to) >
            well.balanceOf(address(xerc20Lockbox))
            ? well.balanceOf(address(xerc20Lockbox))
            : xwell.balanceOf(to);

        /// at minimum mint 1 xWELL
        amount = uint112(_bound(amount, 1, amtCeiling));

        xwell.approve(address(xerc20Lockbox), amount);

        xerc20Lockbox.withdrawTo(to, amount);

        unchecked {
            userBalances[to] -= amount;
            totalSupply -= amount;
        }
    }

    /// minting
    /// @notice should not revert, but can
    function mintToUser(uint224 amount, uint8 user) external {
        amount = uint224(
            _bound(amount, 1, xwell.maxSupply() - xwell.totalSupply())
        );

        address to = users[(_bound(user, 0, users.length - 1))];

        xwell.mint(to, amount);

        /// @dev if an overflow occurs, an invariant will be violated
        unchecked {
            userBalances[to] += amount;
            totalSupply += amount;
        }
    }

    /// burning
    /// @notice should not revert, but can if a user has no balance
    function burnFromUser(uint224 amount, uint8 user) external {
        address to = users[(_bound(user, 0, users.length - 1))];

        amount = uint224(_bound(amount, 1, xwell.balanceOf(address(to))));

        vm.prank(to);
        xwell.approve(address(this), amount);

        xwell.burn(to, amount);

        unchecked {
            userBalances[to] -= amount;
            totalSupply -= amount;
        }
    }
}
