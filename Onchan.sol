// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/*
   ____                 _                
  / __ \               | |               
 | |  | | _ __    ___  | |__    __ _   _ __  
 | |  | || '_ \  / __| | '_ \  / _` | | '_ \ 
 | |__| || | | || (__  | | | || (_| | | | | |
  \____/ |_| |_| \___| |_| |_| \__,_| |_| |_|
                                       
*/

import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/StringsUpgradeable.sol";

contract Onchan is Initializable, UUPSUpgradeable, OwnableUpgradeable, ReentrancyGuardUpgradeable, PausableUpgradeable {
    using StringsUpgradeable for string;

    struct DailyPopularTitles {
        uint256 date;
        uint256[20] titleIds;
        uint256[20] entryCounts;
    }

    struct UserBasic {
        uint256 id;
        string username;
        string bio;
        UserLevel level;
        bool isRegistered;
        uint256 registrationTimestamp;
    }

    struct UserStats {
        uint256 entryCount;
        uint256 dailyEntryCount;
        uint256 dailyTitleCount;
        uint256 lastResetBlock;
        uint256 totalLikes;
        uint256 lastUsernameChangeTimestamp;
        uint256 followingCount;
        uint256 followersCount;
    }

    struct UserSearchResult {
        uint256 id;
        string username;
        UserLevel level;
    }

    struct Entry {
        uint256 id;
        uint256 titleId;
        address author;
        string content;
        uint256 likes;
        uint256 dislikes;
        bool isDeleted;
        bool isEdited;
        uint256 creationBlock;
        uint256 creationTimestamp;
    }

    struct Title {
        uint256 id;
        string name;
        address creator;
        uint256 totalEntries;
        uint256 totalLikes;
        uint256 creationTimestamp;
    }

    enum UserLevel { Newbie, Anon, Based }

    uint256 public registrationFee;
    uint256 public titleCreationFee;
    uint256 public entryFee;
    uint256 public FREE_DAILY_TITLES;
    uint256 public FREE_DAILY_ENTRIES;
    uint256 public additionalTitleFee;
    uint256 public additionalEntryFee;
    uint256 public MAX_TITLE_LENGTH;
    uint256 public MAX_ENTRY_LENGTH;
    uint256 public MAX_BIO_LENGTH;
    uint256 public USERNAME_CHANGE_COOLDOWN;

    uint256 public titleCounter;
    uint256 public entryCounter;
    uint256 public userCounter;
    uint256 public totalUsers;
    uint256 public totalEntries;
    uint256 public totalLikes;

    DailyPopularTitles public todaysPopularTitles;
    DailyPopularTitles public yesterdaysPopularTitles;

    mapping(address => UserBasic) public usersBasic;
    mapping(address => UserStats) public usersStats;
    mapping(address => uint256[]) public userEntryIds;
    mapping(uint256 => address) public userIdToAddress;
    mapping(string => uint256) internal  normalizedUsernameToId;
    mapping(uint256 => Title) public titles;
    mapping(uint256 => Entry) public entries;
    mapping(string => uint256) internal  normalizedTitleNameToId;
    mapping(string => uint256[]) private usernameSearchIndex;
    mapping(string => uint256[]) internal  titleSearchIndex;
    mapping(address => mapping(address => bool)) public following;
    mapping(address => mapping(uint256 => int8)) private userReactions;
    mapping(bytes32 => uint256[]) private usernamePrefix;
    mapping(bytes32 => uint256) private usernameExact;

    event UserRegistered(uint256 indexed userId, address indexed userAddress, string username, uint256 registrationTimestamp);
    event UserProfileUpdated(uint256 indexed userId, address indexed userAddress, string newUsername, string newBio);
    event TitleCreated(uint256 indexed titleId, string name, address creator, uint256 creationTimestamp);
    event EntryAdded(uint256 indexed titleId, uint256 indexed entryId, address author, uint256 creationTimestamp);
    event EntryEdited(uint256 indexed entryId, address author);
    event EntryDeleted(uint256 indexed entryId, address author);
    event EntryLiked(uint256 indexed entryId, address liker);
    event EntryDisliked(uint256 indexed entryId, address disliker);
    event UserLevelUp(uint256 indexed userId, address indexed userAddress, UserLevel newLevel);
    event UserFollowed(address indexed follower, address indexed followed);
    event UserUnfollowed(address indexed follower, address indexed unfollowed);
    event ReactionRemoved(uint256 indexed entryId, address user);
    event TitleDeleted(uint256 indexed titleId, address deleter);
    event TitleNameChanged(uint256 indexed titleId, string oldName, string newName);
    event TitleDeletionDetails(uint256 indexed titleId, uint256 deletedEntries, uint256 remainingEntries);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize() public virtual initializer {
        __Ownable_init();
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();
        __Pausable_init();

        registrationFee = 0;
        titleCreationFee = 0;
        entryFee = 0;
        FREE_DAILY_TITLES = 5;
        FREE_DAILY_ENTRIES = 5;
        additionalTitleFee = 0;
        additionalEntryFee = 0;
        MAX_TITLE_LENGTH = 69;
        MAX_ENTRY_LENGTH = 4000;
        MAX_BIO_LENGTH = 160;
        USERNAME_CHANGE_COOLDOWN = 30 days;
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    modifier onlyRegistered() {
        require(usersBasic[msg.sender].isRegistered, "Not registered");
        _;
    }

    // Helper Functions
    function normalizeTitleString(string memory _input) public virtual pure returns (string memory) {
        bytes memory inputBytes = bytes(_input);
        bytes memory result = new bytes(inputBytes.length);
        uint resultLength = 0;
        for (uint i = 0; i < inputBytes.length; i++) {
            bytes1 char = inputBytes[i];
            if (char != 0x20) {
                if (uint8(char) >= 65 && uint8(char) <= 90) {
                    result[resultLength] = bytes1(uint8(char) + 32);
                } else {
                    result[resultLength] = char;
                }
                resultLength++;
            }
        }
        bytes memory finalResult = new bytes(resultLength);
        for (uint i = 0; i < resultLength; i++) {
            finalResult[i] = result[i];
        }
        return string(finalResult);
    }

    function normalizeAndValidateUsername(string memory _username) public virtual pure returns (string memory) {
        bytes memory usernameBytes = bytes(_username);
        bytes memory result = new bytes(usernameBytes.length);
        for (uint i = 0; i < usernameBytes.length; i++) {
            require(usernameBytes[i] != 0x20, "Username cannot contain spaces");
            if (usernameBytes[i] >= 0x41 && usernameBytes[i] <= 0x5A) {
                result[i] = bytes1(uint8(usernameBytes[i]) + 32);
            } else {
                result[i] = usernameBytes[i];
            }
        }
        return string(result);
    }

    function register(string memory _username, string memory _bio) external virtual payable whenNotPaused nonReentrant {
        string memory normalizedUsername = normalizeAndValidateUsername(_username);
        require(!usersBasic[msg.sender].isRegistered, "Already registered");
        require(normalizedUsernameToId[normalizedUsername] == 0, "Username taken");
        require(bytes(_username).length > 0, "Empty username");
        require(bytes(_bio).length <= MAX_BIO_LENGTH, "Bio too long");
        require(msg.value == registrationFee, "Incorrect fee amount");

        userCounter++;
        usersBasic[msg.sender] = UserBasic({
            id: userCounter,
            username: _username,
            bio: _bio,
            level: UserLevel.Newbie,
            isRegistered: true,
            registrationTimestamp: block.timestamp
        });

        usersStats[msg.sender] = UserStats({
            entryCount: 0,
            dailyEntryCount: 0,
            dailyTitleCount: 0,
            lastResetBlock: block.number,
            totalLikes: 0,
            lastUsernameChangeTimestamp: block.timestamp,
            followingCount: 0,
            followersCount: 0
        });

        normalizedUsernameToId[normalizedUsername] = userCounter;
        userIdToAddress[userCounter] = msg.sender;
        usernameSearchIndex[normalizedUsername].push(userCounter);

        totalUsers++;

        updateUsernameIndexes(_username, userCounter);

        emit UserRegistered(userCounter, msg.sender, _username, block.timestamp);
    }

    function updateProfile(string memory _newUsername, string memory _newBio) external virtual whenNotPaused onlyRegistered nonReentrant {
        require(bytes(_newBio).length <= MAX_BIO_LENGTH, "Bio too long");
        
        UserBasic storage userBasic = usersBasic[msg.sender];
        UserStats storage userStats = usersStats[msg.sender];
        string memory normalizedNewUsername = normalizeAndValidateUsername(_newUsername);
        string memory normalizedOldUsername = normalizeAndValidateUsername(userBasic.username);
        
        if (!StringsUpgradeable.equal(normalizedNewUsername, normalizedOldUsername)) {
            require(block.timestamp >= userStats.lastUsernameChangeTimestamp + USERNAME_CHANGE_COOLDOWN, "Change not allowed yet");
            require(normalizedUsernameToId[normalizedNewUsername] == 0, "Username taken");
            
            delete normalizedUsernameToId[normalizedOldUsername];
            normalizedUsernameToId[normalizedNewUsername] = userBasic.id;

            removeFromSearchIndex(usernameSearchIndex[normalizedOldUsername], userBasic.id);
            delete usernameSearchIndex[normalizedOldUsername];

            usernameSearchIndex[normalizedNewUsername].push(userBasic.id);

            userBasic.username = _newUsername;
            updateUsernameIndexes(_newUsername, userBasic.id);
            userStats.lastUsernameChangeTimestamp = block.timestamp;
        }

        if (!StringsUpgradeable.equal(_newBio, userBasic.bio)) {
            userBasic.bio = _newBio;
        }

        emit UserProfileUpdated(userBasic.id, msg.sender, _newUsername, _newBio);
    }

    function createTitle(string memory _name) external virtual payable whenNotPaused onlyRegistered nonReentrant {
        require(bytes(_name).length > 0 && bytes(_name).length <= MAX_TITLE_LENGTH, "Invalid title length");
        string memory normalizedName = normalizeTitleString(_name);
        require(normalizedTitleNameToId[normalizedName] == 0, "Title name already exists");
        
        resetDailyCountsIfNeeded(msg.sender);

        uint256 requiredFee = titleCreationFee;
        if (usersStats[msg.sender].dailyTitleCount >= FREE_DAILY_TITLES) {
            requiredFee += additionalTitleFee;
        }
        require(msg.value == requiredFee, "Incorrect fee amount");

        titleCounter++;
        titles[titleCounter] = Title(titleCounter, _name, msg.sender, 0, 0, block.timestamp);
        normalizedTitleNameToId[normalizedName] = titleCounter;
        titleSearchIndex[normalizedName].push(titleCounter);

        usersStats[msg.sender].dailyTitleCount++;

        emit TitleCreated(titleCounter, _name, msg.sender, block.timestamp);
    }

    function addEntry(uint256 _titleId, string memory _content) public virtual payable whenNotPaused onlyRegistered nonReentrant {
        require(_titleId > 0 && _titleId <= titleCounter, "Invalid title ID");
        require(bytes(_content).length > 0 && bytes(_content).length <= MAX_ENTRY_LENGTH, "Invalid entry length");

        resetDailyCountsIfNeeded(msg.sender);

        uint256 requiredFee = entryFee;
        if (usersStats[msg.sender].dailyEntryCount >= FREE_DAILY_ENTRIES) {
            requiredFee += additionalEntryFee;
        }
        require(msg.value == requiredFee, "Incorrect fee amount");

        entryCounter++;
        entries[entryCounter] = Entry(entryCounter, _titleId, msg.sender, _content, 0, 0, false, false, block.number, block.timestamp);
        titles[_titleId].totalEntries++;

        usersStats[msg.sender].entryCount++;
        usersStats[msg.sender].dailyEntryCount++;
        userEntryIds[msg.sender].push(entryCounter);
        totalEntries++;
        
        updateDailyEntryCount(todaysPopularTitles, _titleId, block.timestamp / 1 days);
        checkAndUpdateUserLevel(msg.sender);

        emit EntryAdded(_titleId, entryCounter, msg.sender, block.timestamp);
    }

    function editEntry(uint256 _entryId, string memory _newContent) external virtual whenNotPaused onlyRegistered nonReentrant {
        require(_entryId > 0 && _entryId <= entryCounter, "Invalid entry ID");
        require(entries[_entryId].author == msg.sender, "Not the author");
        require(!entries[_entryId].isDeleted, "Entry deleted");
        require(bytes(_newContent).length > 0 && bytes(_newContent).length <= MAX_ENTRY_LENGTH, "Invalid entry length");
        entries[_entryId].content = _newContent;
        entries[_entryId].isEdited = true;

        emit EntryEdited(_entryId, msg.sender);
    }

    function deleteEntry(uint256 _entryId) external virtual whenNotPaused onlyRegistered nonReentrant {
        require(_entryId > 0 && _entryId <= entryCounter, "Invalid entry ID");
        require(entries[_entryId].author == msg.sender, "Not the author");
        require(!entries[_entryId].isDeleted, "Already deleted");

        entries[_entryId].isDeleted = true;
        usersStats[msg.sender].entryCount--;
        titles[entries[_entryId].titleId].totalEntries--;
        totalEntries--;

        checkAndUpdateUserLevel(msg.sender);

        emit EntryDeleted(_entryId, msg.sender);
    }

    function likeEntry(uint256 _entryId) external virtual whenNotPaused onlyRegistered nonReentrant {
        require(_entryId > 0 && _entryId <= entryCounter, "Invalid entry ID");
        require(!entries[_entryId].isDeleted, "Entry deleted");
        
        int8 currentReaction = userReactions[msg.sender][_entryId];
        require(currentReaction != 1, "Already liked");

        if (currentReaction == -1) {
            entries[_entryId].dislikes--;
        }

        entries[_entryId].likes++;
        usersStats[entries[_entryId].author].totalLikes++;
        titles[entries[_entryId].titleId].totalLikes++;
        totalLikes++;

        userReactions[msg.sender][_entryId] = 1;

        emit EntryLiked(_entryId, msg.sender);
    }

    function dislikeEntry(uint256 _entryId) external virtual whenNotPaused onlyRegistered nonReentrant {
        require(_entryId > 0 && _entryId <= entryCounter, "Invalid entry ID");
        require(!entries[_entryId].isDeleted, "Entry deleted");

        int8 currentReaction = userReactions[msg.sender][_entryId];
        require(currentReaction != -1, "Already disliked");

        if (currentReaction == 1) {
            entries[_entryId].likes--;
            usersStats[entries[_entryId].author].totalLikes--;
            titles[entries[_entryId].titleId].totalLikes--;
            totalLikes--;
        }

        entries[_entryId].dislikes++;
        userReactions[msg.sender][_entryId] = -1;

        emit EntryDisliked(_entryId, msg.sender);
    }

    function removeReaction(uint256 _entryId) external virtual whenNotPaused onlyRegistered nonReentrant {
        require(_entryId > 0 && _entryId <= entryCounter, "Invalid entry ID");
        require(!entries[_entryId].isDeleted, "Entry deleted");

        int8 currentReaction = userReactions[msg.sender][_entryId];
        require(currentReaction != 0, "No reaction to remove");

        if (currentReaction == 1) {
            entries[_entryId].likes--;
            usersStats[entries[_entryId].author].totalLikes--;
            titles[entries[_entryId].titleId].totalLikes--;
            totalLikes--;
        } else if (currentReaction == -1) {
            entries[_entryId].dislikes--;
        }

        userReactions[msg.sender][_entryId] = 0;

        emit ReactionRemoved(_entryId, msg.sender);
    }

    function getUserReaction(address _user, uint256 _entryId) external virtual view returns (int8) {
        return userReactions[_user][_entryId];
    }

    function followUser(address _userToFollow) external virtual whenNotPaused onlyRegistered nonReentrant {
        require(_userToFollow != msg.sender, "Cannot self-follow");
        require(usersBasic[_userToFollow].isRegistered, "User not registered");
        require(!following[msg.sender][_userToFollow], "Already following");

        following[msg.sender][_userToFollow] = true;
        usersStats[msg.sender].followingCount++;
        usersStats[_userToFollow].followersCount++;
        emit UserFollowed(msg.sender, _userToFollow);
    }

    function unfollowUser(address _userToUnfollow) external virtual whenNotPaused onlyRegistered nonReentrant {
        require(following[msg.sender][_userToUnfollow], "Not following");

        following[msg.sender][_userToUnfollow] = false;
        usersStats[msg.sender].followingCount--;
        usersStats[_userToUnfollow].followersCount--;
        emit UserUnfollowed(msg.sender, _userToUnfollow);
    }

    function getFollowingCount(address _user) public virtual view returns (uint256) {
        return usersStats[_user].followingCount;
    }

    function getFollowersCount(address _user) public virtual view returns (uint256) {
        return usersStats[_user].followersCount;
    }

    function isUsernameAvailable(string memory _username) public virtual view returns (bool) {
        return normalizedUsernameToId[normalizeAndValidateUsername(_username)] == 0;
    }

    function isTitleNameAvailable(string memory _name) public virtual view returns (bool) {
        return normalizedTitleNameToId[normalizeTitleString(_name)] == 0;
    }

    function getTopTwentyPopularTitles(bool _today) external virtual view returns (uint256[20] memory, uint256[20] memory) {
        if (_today) {
            return (todaysPopularTitles.titleIds, todaysPopularTitles.entryCounts);
        } else {
            return (yesterdaysPopularTitles.titleIds, yesterdaysPopularTitles.entryCounts);
        }
    }

    function getPlatformStats() external virtual view returns (uint256, uint256, uint256) {
        return (totalUsers, totalEntries, totalLikes);
    }

    function getUserStats(uint256 _userId) external virtual view returns (uint256, uint256, UserLevel, uint256, uint256, uint256) {
        address userAddress = userIdToAddress[_userId];
        require(usersBasic[userAddress].isRegistered, "User not registered");
        UserBasic storage userBasic = usersBasic[userAddress];
        UserStats storage userStats = usersStats[userAddress];
        return (userStats.entryCount, userStats.totalLikes, userBasic.level, userBasic.registrationTimestamp, userStats.followingCount, userStats.followersCount);
    }

    function getUserByUsername(string memory _username) external virtual view returns (uint256, address, UserLevel, uint256, uint256, uint256) {
        uint256 userId = normalizedUsernameToId[normalizeAndValidateUsername(_username)];
        require(userId != 0, "User not found");
        address userAddress = userIdToAddress[userId];
        UserBasic storage userBasic = usersBasic[userAddress];
        UserStats storage userStats = usersStats[userAddress];
        return (userBasic.id, userAddress, userBasic.level, userBasic.registrationTimestamp, userStats.followingCount, userStats.followersCount);
    }

    function getUsernameById(uint256 _userId) external virtual view returns (string memory) {
        address userAddress = userIdToAddress[_userId];
        require(usersBasic[userAddress].isRegistered, "User not registered");
        return usersBasic[userAddress].username;
    }

    function getUserEntryCount(address _user) external virtual view returns (uint256) {
        return userEntryIds[_user].length;
    }

    function getUserEntryIdByIndex(address _user, uint256 _index) external virtual view returns (uint256) {
        require(_index < userEntryIds[_user].length, "Invalid index");
        return userEntryIds[_user][_index];
    }

    function getUserDailyTitleCount(address _user) external virtual view returns (uint256) {
        return usersStats[_user].dailyTitleCount;
    }

    function getUserDailyEntryCount(address _user) external virtual view returns (uint256) {
        return usersStats[_user].dailyEntryCount;
    }

    function searchUsers(string memory _query, uint256 _page, uint256 _perPage) public virtual view returns (UserSearchResult[] memory) {
        UserSearchResult[] memory results = new UserSearchResult[](_perPage);
        uint256 resultCount = 0;

        bytes32 exactHash = keccak256(abi.encodePacked(toLower(_query)));
        uint256 exactMatchId = usernameExact[exactHash];
        if (exactMatchId != 0) {
            address userAddress = userIdToAddress[exactMatchId];
            UserBasic storage userBasic = usersBasic[userAddress];
            results[resultCount] = UserSearchResult(userBasic.id, userBasic.username, userBasic.level);
            resultCount++;
        }

        if (resultCount < _perPage) {
            bytes32 prefix = keccak256(abi.encodePacked(toLower(substring(_query, 0, 3))));
            uint256[] storage matchingIds = usernamePrefix[prefix];
            
            uint256 start = (_page - 1) * _perPage;
            uint256 end = start + (_perPage - resultCount);
            if (end > matchingIds.length) end = matchingIds.length;
            
            for (uint256 i = start; i < end && resultCount < _perPage; i++) {
                address userAddress = userIdToAddress[matchingIds[i]];
                if (usersBasic[userAddress].isRegistered && 
                    startsWith(toLower(usersBasic[userAddress].username), toLower(_query)) &&
                    matchingIds[i] != exactMatchId) {
                    UserBasic storage userBasic = usersBasic[userAddress];
                    results[resultCount] = UserSearchResult(userBasic.id, userBasic.username, userBasic.level);
                    resultCount++;
                }
            }
        }

        assembly {
            mstore(results, resultCount)
        }

        return results;
    }

    function searchTitles(string memory _query, uint256 _limit) public virtual view returns (Title[] memory) {
        Title[] memory matchedTitles = new Title[](_limit);
        uint256 matchCount = 0;
        string memory lowercaseQuery = toLower(_query);

        for (uint256 i = 1; i <= titleCounter && matchCount < _limit; i++) {
            if (bytes(titles[i].name).length > 0) {
                string memory lowercaseTitle = toLower(titles[i].name);
                if (contains(lowercaseTitle, lowercaseQuery)) {
                    matchedTitles[matchCount] = titles[i];
                    matchCount++;
                }
            }
        }

        assembly {
            mstore(matchedTitles, matchCount)
        }

        return matchedTitles;
    }

    function contains(string memory _haystack, string memory _needle) internal pure returns (bool) {
        bytes memory haystackBytes = bytes(_haystack);
        bytes memory needleBytes = bytes(_needle);

        if (needleBytes.length > haystackBytes.length) {
            return false;
        }

        for (uint i = 0; i <= haystackBytes.length - needleBytes.length; i++) {
            bool found = true;
            for (uint j = 0; j < needleBytes.length; j++) {
                if (haystackBytes[i + j] != needleBytes[j]) {
                    found = false;
                    break;
                }
            }
            if (found) {
                return true;
            }
        }
        return false;
    }

    function toLower(string memory _str) internal pure returns (string memory) {
        bytes memory strBytes = bytes(_str);
        bytes memory result = new bytes(strBytes.length);
        for (uint i = 0; i < strBytes.length; i++) {
            if (strBytes[i] >= 0x41 && strBytes[i] <= 0x5A) {
                result[i] = bytes1(uint8(strBytes[i]) + 32);
            } else {
                result[i] = strBytes[i];
            }
        }
        return string(result);
    }

    function getTitleEntryIds(uint256 _titleId) internal view returns (uint256[] memory) {
        require(_titleId > 0 && _titleId <= titleCounter, "Invalid title ID");
        uint256[] memory entryIds = new uint256[](titles[_titleId].totalEntries);
        uint256 count = 0;
        for (uint256 i = 1; i <= entryCounter; i++) {
            if (entries[i].titleId == _titleId && !entries[i].isDeleted) {
                entryIds[count] = i;
                count++;
            }
        }
        assembly {
            mstore(entryIds, count)
        }
        return entryIds;
    }

    function isFollowing(address _follower, address _followed) public virtual view returns (bool) {
        return following[_follower][_followed];
    }

    function resetDailyCountsIfNeeded(address _user) internal {
        if (block.number >= usersStats[_user].lastResetBlock + (1 days / 12)) {
            usersStats[_user].dailyEntryCount = 0;
            usersStats[_user].dailyTitleCount = 0;
            usersStats[_user].lastResetBlock = block.number;
        }
    }

    function checkAndUpdateUserLevel(address _user) internal {
        UserBasic storage userBasic = usersBasic[_user];
        UserStats storage userStats = usersStats[_user];
        UserLevel newLevel = userBasic.level;

        if (userStats.entryCount >= 100) {
            newLevel = UserLevel.Based;
        } else if (userStats.entryCount >= 50) {
            newLevel = UserLevel.Anon;
        } else if (userStats.entryCount >= 10) {
            newLevel = UserLevel.Newbie;
        }

        if (newLevel != userBasic.level) {
            userBasic.level = newLevel;
            emit UserLevelUp(userBasic.id, _user, newLevel);
        }
    }

    function getEmptyArray() internal pure returns (uint256[20] memory) {
        return [uint256(0), 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0];
    }

    function updateDailyEntryCount(DailyPopularTitles storage self, uint256 _titleId, uint256 currentDate) internal {
        if (currentDate > self.date) {
            self.date = currentDate;
            self.titleIds = getEmptyArray();
            self.entryCounts = getEmptyArray();
        }

        uint256 currentCount = 0;
        uint256 i;
        for (i = 0; i < 20; i++) {
            if (self.titleIds[i] == _titleId) {
                currentCount = self.entryCounts[i];
                break;
            }
        }
        updateTopTwenty(self, _titleId, currentCount + 1);
    }

    function updateTopTwenty(DailyPopularTitles storage self, uint256 _titleId, uint256 _newCount) private {
        uint256 lowestIndex = 19;
        uint256 i;
        for (i = 0; i < 20; i++) {
            if (self.titleIds[i] == _titleId) {
                self.entryCounts[i] = _newCount;
                return;
            }
            if (self.entryCounts[i] < self.entryCounts[lowestIndex]) {
                lowestIndex = i;
            }
        }

        if (_newCount > self.entryCounts[lowestIndex]) {
            self.titleIds[lowestIndex] = _titleId;
            self.entryCounts[lowestIndex] = _newCount;
        }
    }

    function removeFromSearchIndex(uint256[] storage array, uint256 value) internal {
        for (uint256 i = 0; i < array.length; i++) {
            if (array[i] == value) {
                array[i] = array[array.length - 1];
                array.pop();
                break;
            }
        }
    }

    function pause() external virtual onlyOwner {
        _pause();
    }

    function unpause() external virtual onlyOwner {
        _unpause();
    }

    function setRegistrationFee(uint256 _fee) external virtual onlyOwner {
        registrationFee = _fee;
    }

    function setTitleCreationFee(uint256 _fee) external virtual onlyOwner {
        titleCreationFee = _fee;
    }

    function setAdditionalTitleFee(uint256 _fee) external virtual onlyOwner {
        additionalTitleFee = _fee;
    }

    function setEntryFee(uint256 _fee) external virtual onlyOwner {
        entryFee = _fee;
    }

    function setAdditionalEntryFee(uint256 _fee) external virtual onlyOwner {
        additionalEntryFee = _fee;
    }

    function setFreeDailyTitles(uint256 _count) external virtual onlyOwner {
        FREE_DAILY_TITLES = _count;
    }

    function setFreeDailyEntries(uint256 _count) external virtual onlyOwner {
        FREE_DAILY_ENTRIES = _count;
    }

    function setMaxTitleLength(uint256 _newLength) external virtual onlyOwner {
        MAX_TITLE_LENGTH = _newLength;
    }

    function setMaxEntryLength(uint256 _newLength) external virtual onlyOwner {
        MAX_ENTRY_LENGTH = _newLength;
    }

    function setMaxBioLength(uint256 _newLength) external virtual onlyOwner {
        MAX_BIO_LENGTH = _newLength;
    }

    function setUsernameChangeCooldown(uint256 _newCooldown) external virtual onlyOwner {
        USERNAME_CHANGE_COOLDOWN = _newCooldown;
    }

    function withdrawFunds() external virtual onlyOwner nonReentrant {
        uint256 balance = address(this).balance;
        address owner = owner();
        (bool success, ) = payable(owner).call{value: balance}("");
        require(success, "Withdrawal failed");
    }

    function deleteTitle(uint256 _titleId) external virtual onlyOwner {
        require(_titleId > 0 && _titleId <= titleCounter, "Invalid title ID");
        require(titles[_titleId].id != 0, "Title does not exist");

        string memory normalizedName = normalizeTitleString(titles[_titleId].name);
        delete normalizedTitleNameToId[normalizedName];

        uint256 deletedEntries = 0;
        uint256[] memory titleEntries = getTitleEntryIds(_titleId);
        for (uint256 i = 0; i < titleEntries.length; i++) {
            uint256 entryId = titleEntries[i];
            if (!entries[entryId].isDeleted) {
                entries[entryId].isDeleted = true;
                deletedEntries++;
                emit EntryDeleted(entryId, entries[entryId].author);
            }
        }

        if (deletedEntries <= totalEntries) {
            totalEntries -= deletedEntries;
        } else {
            totalEntries = 0;
        }

        uint256 titleTotalEntries = titles[_titleId].totalEntries;
        if (titleTotalEntries <= totalEntries) {
            totalEntries -= titleTotalEntries;
        } else {
            totalEntries = 0;
        }

        delete titles[_titleId];

        emit TitleDeleted(_titleId, msg.sender);
        emit TitleDeletionDetails(_titleId, deletedEntries, totalEntries);
    }

    function changeTitleName(uint256 _titleId, string memory _newName) external virtual onlyOwner {
        require(_titleId > 0 && _titleId <= titleCounter, "Invalid title ID");
        require(titles[_titleId].id != 0, "Title does not exist");
        require(isTitleNameAvailable(_newName), "New title name is not available");

        string memory oldName = titles[_titleId].name;
        string memory normalizedOldName = normalizeTitleString(oldName);
        string memory normalizedNewName = normalizeTitleString(_newName);

        delete normalizedTitleNameToId[normalizedOldName];
        normalizedTitleNameToId[normalizedNewName] = _titleId;

        titles[_titleId].name = _newName;

        emit TitleNameChanged(_titleId, oldName, _newName);
    }

    function deleteEntryByOwner(uint256 _entryId) external virtual onlyOwner {
        require(_entryId > 0 && _entryId <= entryCounter, "Invalid entry ID");
        require(!entries[_entryId].isDeleted, "Entry already deleted");

        entries[_entryId].isDeleted = true;
        totalEntries--;
        titles[entries[_entryId].titleId].totalEntries--;

        emit EntryDeleted(_entryId, entries[_entryId].author);
    }

    function getTitleEntriesPaginated(uint256 _titleId, uint256 _page, uint256 _perPage) public virtual view returns (uint256[] memory) {
        require(_titleId > 0 && _titleId <= titleCounter, "Invalid title ID");
        uint256 start = (_page - 1) * _perPage;
        uint256 end = start + _perPage;
        uint256[] memory entryIds = new uint256[](_perPage);
        uint256 count = 0;
        uint256 entryCount = 0;

        for (uint256 i = 1; i <= entryCounter && count < _perPage; i++) {
            if (entries[i].titleId == _titleId && !entries[i].isDeleted) {
                if (entryCount >= start && entryCount < end) {
                    entryIds[count] = i;
                    count++;
                }
                entryCount++;
            }
        }

        assembly {
            mstore(entryIds, count)
        }

        return entryIds;
    }

    function getRandomTitles(uint256 count) public virtual view returns (uint256[] memory) {
        require(count > 0 && count <= 5, "Invalid count");
        uint256[] memory randomIds = new uint256[](count);
        uint256[] memory availableTitles = new uint256[](titleCounter);
        uint256 availableCount = 0;

        for (uint256 i = 1; i <= titleCounter; i++) {
            if (titles[i].id != 0) {
                availableTitles[availableCount] = i;
                availableCount++;
            }
        }

        if (availableCount <= count) {
            return availableTitles;
        }

        for (uint256 i = 0; i < count; i++) {
            uint256 randomIndex = uint256(keccak256(abi.encodePacked(block.timestamp, block.prevrandao, i))) % availableCount;
            randomIds[i] = availableTitles[randomIndex];
            availableTitles[randomIndex] = availableTitles[availableCount - 1];
            availableCount--;
        }

        return randomIds;
    }

function getUserEntriesPaginated(address _user, uint256 _page, uint256 _perPage) public virtual view returns (uint256[] memory) {
    uint256 start = (_page - 1) * _perPage;
    uint256[] memory entryIds = new uint256[](_perPage);
    uint256 userEntryCount = userEntryIds[_user].length;
    uint256 count = 0;
    uint256 validEntries = 0;

    for (uint256 i = 0; i < userEntryCount && count < _perPage; i++) {
        uint256 entryId = userEntryIds[_user][i];
        if (!entries[entryId].isDeleted && titles[entries[entryId].titleId].id != 0) {
            if (validEntries >= start) {
                entryIds[count] = entryId;
                count++;
            }
            validEntries++;
        }
    }

    assembly {
        mstore(entryIds, count)
    }

    return entryIds;
}

    function getRegistrationFee() external virtual view returns (uint256) {
        return registrationFee;
    }

    function updateUsernameIndexes(string memory username, uint256 userId) internal {
        bytes32 prefix = keccak256(abi.encodePacked(toLower(substring(username, 0, 3))));
        usernamePrefix[prefix].push(userId);
        
        bytes32 exactHash = keccak256(abi.encodePacked(toLower(username)));
        usernameExact[exactHash] = userId;
    }

    function substring(string memory str, uint256 startIndex, uint256 length) private pure returns (string memory) {
        bytes memory strBytes = bytes(str);
        if (startIndex + length > strBytes.length) {
            length = strBytes.length - startIndex;
        }
        bytes memory result = new bytes(length);
        for(uint i = 0; i < length; i++) {
            result[i] = strBytes[startIndex + i];
        }
        return string(result);
    }

    function startsWith(string memory _base, string memory _value) private pure returns (bool) {
        bytes memory baseBytes = bytes(_base);
        bytes memory valueBytes = bytes(_value);

        if (valueBytes.length > baseBytes.length) {
            return false;
        }

        for (uint i = 0; i < valueBytes.length; i++) {
            if (baseBytes[i] != valueBytes[i]) {
                return false;
            }
        }

        return true;
    }
}