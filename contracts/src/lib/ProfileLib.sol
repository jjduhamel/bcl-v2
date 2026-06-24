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
    string  agentFramework;   // e.g. Openclaw / Hermes
    string  baseModel;        // e.g. Claude Opus 4.8
    string  modelVersion;     // e.g. Stockfish
    uint40  createdAt;
  }

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

  function profile(PlayerData storage data) public view returns (PlayerProfile storage) {
    return data.__profile;
  }

  function statistics(PlayerData storage data) public view returns (AccountStats storage) {
    return data.__stats;
  }

  function register(
    PlayerProfile storage profile,
    string calldata username,
    string calldata avatar
  ) public {
    profile.username = username;
    profile.avatar = avatar;
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

  function profile(RobotData storage data) public view returns (RobotProfile storage) {
    return data.__profile;
  }

  function statistics(RobotData storage data) public view returns (AccountStats storage) {
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
    profile.nickname = nickname;
    profile.avatar = avatar;
    profile.agentFramework = agentFramework;
    profile.baseModel = baseModel;
    profile.modelVersion = modelVersion;
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
  function suspend(RobotProfile storage profile, bool value) public {
    profile.active = !value;
  }
}

library PlayerLobby {
  using EnumerableSet for EnumerableSet.UintSet;
  using EnumerableSet for EnumerableSet.AddressSet;

  struct PlayerLobby {
    EnumerableSet.UintSet __pendingChallenges;
    EnumerableSet.UintSet __currentGames;
    EnumerableSet.UintSet __finishedGames;
    EnumerableSet.UintSet __disputes;
    EnumerableSet.AddressSet __robots;
  }

  function hasChallenge(PlayerLobby storage lobby, uint gameId) internal view returns (bool) {
    return lobby.__pendingChallenges.contains(gameId);
  }

  function challenges(PlayerLobby storage lobby) internal view returns (uint[] memory) {
    return lobby.__pendingChallenges.values();
  }

  function games(PlayerLobby storage lobby) internal view returns (uint[] memory) {
    return lobby.__currentGames.values();
  }

  function history(PlayerLobby storage lobby) internal view returns (uint[] memory) {
    return lobby.__finishedGames.values();
  }

  function challenge(PlayerLobby storage lobby, uint gameId) internal {
    lobby.__pendingChallenges.add(gameId);
  }

  function accept(PlayerLobby storage lobby, uint gameId) internal {
    lobby.__pendingChallenges.remove(gameId);
    lobby.__currentGames.add(gameId);
  }

  // Used by address(0) to track all games
  function track(PlayerLobby storage lobby, uint gameId) internal {
    lobby.__currentGames.add(gameId);
  }

  function decline(PlayerLobby storage lobby, uint gameId) internal {
    lobby.__pendingChallenges.remove(gameId);
  }

  function finish(PlayerLobby storage lobby, uint gameId) internal {
    lobby.__currentGames.remove(gameId);
    lobby.__finishedGames.add(gameId);
  }

  function agents(PlayerLobby storage lobby) internal view returns (address[] memory) {
    return lobby.__robots.values();
  }

  function register(PlayerLobby storage lobby, address robot) internal {
    lobby.__robots.add(robot);
  }

  function unregister(PlayerLobby storage lobby, address robot) internal {
    lobby.__robots.remove(robot);
  }

  function disputes(PlayerLobby storage lobby) internal view returns (uint[] memory) {
    return lobby.__disputes.values();
  }

  function dispute(PlayerLobby storage lobby, uint gameId) internal {
    lobby.__disputes.add(gameId);
  }

  function resolve(PlayerLobby storage lobby, uint gameId) internal {
    lobby.__disputes.remove(gameId);
  }
}

abstract contract ProfileWrapper {
  using PlayerLobby for PlayerLobby.PlayerLobby;
  using ProfileLib for ProfileLib.PlayerProfile;
  using ProfileLib for ProfileLib.RobotProfile;

  // Player Lobby
  mapping(address => PlayerLobby.PlayerLobby) private __lobby;
  mapping(address => ProfileLib.PlayerData) private __players;
  mapping(address => ProfileLib.RobotData) private __robots;
  // Map account -> role -> status
  mapping(address => mapping(bytes32 => bool)) __roles;

  // Reserved slots — decrement when adding state above to preserve layout across upgrades.
  // __disputes (EnumerableSet.UintSet) consumes 2 slots, so this contract uses 6 of 50.
  uint256[44] private __gap;

  function _lobby(address account) internal view
  returns (PlayerLobby.PlayerLobby storage) {
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

  function _agents(address account) internal view
  returns (address[] memory) {
    return _lobby(account).agents();
  }

  function _stats(address account) internal view
  returns (ProfileLib.AccountStats storage) {
    return _agent(account).owner == address(0) ? ProfileLib.statistics(__players[account])
                                               : ProfileLib.statistics(__robots[account]);
  }

  function _register(
    address player,
    string calldata username,
    string calldata avatar
  ) internal {
    _player(player).register(username, avatar);
  }

  function _register(
    address robot,
    address owner,
    string calldata nickname,
    string calldata avatar,
    string calldata agentFramework,
    string calldata baseModel,
    string calldata modelVersion
  ) internal {
    _lobby(msg.sender).register(robot);
    _agent(robot).register(
      owner,
      nickname,
      avatar,
      agentFramework,
      baseModel,
      modelVersion
    );
  }

  function _unregister(address owner, address robot) internal {
    _lobby(owner).unregister(robot);
    delete __robots[robot];
  }

  function _isOpenTable(uint gameId) internal view returns (bool) {
    if (_lobby(address(0)).hasChallenge(gameId)) return true;
    return false;
  }

  function _challenges(address player) internal view returns (uint[] memory) {
    return _lobby(player).challenges();
  }

  function _games(address player) internal view returns (uint[] memory) {
    return _lobby(player).games();
  }

  function _history(address player) internal view returns (uint[] memory) {
    return _lobby(player).history();
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
