// SPDX-License-Identifier: GPL-V3
pragma solidity >=0.4.22 <0.9.0;
import '@oz/utils/structs/EnumerableSet.sol';

// Identity / account profile shapes + the per-profile mutations on them.
//
// Layout: PlayerProfile / RobotProfile are the lean, ABI-returnable structs (no mappings) that
// frontend / MCP read via `playerProfile()` / `agentProfile()`. PlayerData / RobotData wrap that
// profile plus the stats counters and per-account role bits; the wrappers live in Lobby's storage
// maps and never cross the ABI boundary. Library functions take the wrapper by storage ref and
// reach into `__profile` for field updates.
library ProfileLib {
  using EnumerableSet for EnumerableSet.AddressSet;

  struct PlayerLobby {
    EnumerableSet.UintSet pendingChallenges;
    EnumerableSet.UintSet currentGames;
    EnumerableSet.UintSet finishedGames;
    EnumerableSet.AddressSet robots;
  }

  // Game / wager / dispute counters; address(0)'s entry doubles as the platform-wide rollup.
  struct AccountStats {
    uint created;
    uint received;
    uint started;
    uint finished;
    uint victories;
    uint defeats;
    uint draws;
    uint disputes;
    uint disputesWon;
    uint disputesLost;
  }

  struct PlayerProfile {
    string username;
    string avatar;            // Avatar URI
    uint40  createdAt;
  }

  // TODO: Handle maxWager for different token types
  struct RobotProfile {
    address owner;
    bool    active;
    string  nickname;
    string  avatar;           // Avatar URI
    string  agentFramework;   // e.g. Hermes
    string  baseModel;        // e.g. Claude Opus
    string  modelVersion;     // e.g. 4.7
    uint40  createdAt;
  }

  // Wrapper structs holding mapping-bearing state. Stay inside Lobby's storage maps; never
  // returned across the external ABI.
  struct PlayerData {
    PlayerProfile __profile;
    AccountStats __stats;
  }

  struct RobotData {
    RobotProfile __profile;
    AccountStats __stats;
  }

  /*
   * Player Profile
   */

  function profile(PlayerData storage data) internal view returns (PlayerProfile storage) {
    return data.__profile;
  }

  function statistics(PlayerData storage data) internal view returns (AccountStats storage) {
    return data.__stats;
  }

  function register(
    PlayerProfile storage profile,
    string calldata username,
    string calldata avatar
  ) public {
    update(profile, username, avatar);
    profile.createdAt = uint40(block.timestamp);
  }

  function update(
    PlayerProfile storage profile,
    string calldata username,
    string calldata avatar
  ) public {
    profile.username = username;
    profile.avatar = avatar;
  }

  /*
   * Agent Profile
   */

  function profile(RobotData storage data) internal view returns (RobotProfile storage) {
    return data.__profile;
  }

  function statistics(RobotData storage data) internal view returns (AccountStats storage) {
    return data.__stats;
  }

  function register(
    RobotProfile storage profile,
    address owner,
    string calldata nickname,
    string calldata avatar,
    string calldata agentFramework,
    string calldata baseModel,
    string calldata modelVersion
  ) public {
    profile.owner = owner;
    profile.active = true;
    update(profile, nickname, avatar, agentFramework, baseModel, modelVersion);
    profile.createdAt = uint40(block.timestamp);
  }

  function update(
    RobotProfile storage profile,
    string calldata nickname,
    string calldata avatar,
    string calldata agentFramework,
    string calldata baseModel,
    string calldata modelVersion
  ) public {
    profile.nickname = nickname;
    profile.avatar = avatar;
    profile.agentFramework = agentFramework;
    profile.baseModel = baseModel;
    profile.modelVersion = modelVersion;
  }

  // value = true → suspend (active=false); value = false → resume (active=true).
  function suspend(RobotProfile storage profile, bool value) internal {
    profile.active = !value;
  }
}

abstract contract ProfileWrapper {
  using EnumerableSet for EnumerableSet.UintSet;
  using EnumerableSet for EnumerableSet.AddressSet;
  using ProfileLib for ProfileLib.PlayerProfile;
  using ProfileLib for ProfileLib.RobotProfile;

  // Owns agent role assignment because _registerAgent / _unregisterAgent here grant/revoke it.
  bytes32 public constant ROBOT_ROLE = keccak256('ROBOT_ROLE');

  // Player Lobby
  mapping(address => ProfileLib.PlayerLobby) private __lobby;
  mapping(address => ProfileLib.PlayerData) private __players;
  mapping(address => ProfileLib.RobotData) private __robots;
  // Map account -> role -> status
  mapping(address => mapping(bytes32 => bool)) __roles;
  // Disputed game ids
  EnumerableSet.UintSet private __disputes;

  function _lobby(address account) internal view
  returns (ProfileLib.PlayerLobby storage) {
    return __lobby[account];
  }

  function _player(address account) internal view
  returns (ProfileLib.PlayerProfile storage) {
    return ProfileLib.profile(__players[account]);
  }

  function _agent(address account) internal view
  returns (ProfileLib.RobotProfile storage) {
    return ProfileLib.profile(__robots[account]);
  }

  function _stats(address account) internal view
  returns (ProfileLib.AccountStats storage) {
    return _agent(account).owner == address(0) ? ProfileLib.statistics(__players[account])
                                               : ProfileLib.statistics(__robots[account]);
  }

  function _registerPlayer(
    address player,
    string calldata username,
    string calldata avatar
  ) internal {
    _player(player).register(username, avatar);
  }

  function _registerAgent(
    address robot,
    address owner,
    string calldata nickname,
    string calldata avatar,
    string calldata agentFramework,
    string calldata baseModel,
    string calldata modelVersion
  ) internal {
    _agent(robot).register(
      owner,
      nickname,
      avatar,
      agentFramework,
      baseModel,
      modelVersion
    );
    _lobby(msg.sender).robots.add(robot);
    _grantRole(robot, ROBOT_ROLE);
  }

  function _unregisterAgent(address robot) internal {
    _revokeRole(robot, ROBOT_ROLE);
    delete __robots[robot];
  }

  function _disputes() internal view returns (uint[] memory) {
    return __disputes.values();
  }

  function _dispute(uint gameId) internal {
    __disputes.add(gameId);
  }

  function _resolve(uint gameId) internal {
    __disputes.remove(gameId);
  }

  function _hasRole(address account, bytes32 role) internal view
  returns (bool) {
    return __roles[account][role];
  }

  function _grantRole(address account, bytes32 role) internal {
    __roles[account][role] = true;
  }

  function _revokeRole(address account, bytes32 role) internal {
    __roles[account][role] = false;
  }
}
