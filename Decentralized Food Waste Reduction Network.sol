// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

contract DecentralizedFoodWasteReductionNetwork {
    
    enum Status { Available, Reserved, Collected, Expired }
    enum UserType { None, Supplier, Recipient, Both }
    
    struct FoodItem {
        address supplier;
        uint256 quantity;
        uint256 expiryTime;
        uint256 price;
        Status status;
        address recipient;
    }
    
    struct User {
        UserType userType;
        uint256 itemsListed;
        uint256 itemsReceived;
        uint256 reputation;
        uint256 wasteSaved;
    }
    
    // Core mappings
    mapping(uint256 => FoodItem) public items;
    mapping(uint256 => string) public itemNames;
    mapping(uint256 => string) public itemLocations;
    mapping(address => User) public users;
    mapping(address => string) public userNames;
    
    uint256 public itemCount;
    uint256 public totalWasteSaved;
    uint256 public totalItemsListed;
    
    // Events
    event UserRegistered(address indexed user, UserType userType);
    event ItemListed(uint256 indexed itemId, address indexed supplier);
    event ItemReserved(uint256 indexed itemId, address indexed recipient);
    event ItemCollected(uint256 indexed itemId);
    
    modifier onlyRegistered() {
        require(users[msg.sender].userType != UserType.None, "Not registered");
        _;
    }
    
    modifier canSupply() {
        UserType t = users[msg.sender].userType;
        require(t == UserType.Supplier || t == UserType.Both, "Not supplier");
        _;
    }
    
    modifier canReceive() {
        UserType t = users[msg.sender].userType;
        require(t == UserType.Recipient || t == UserType.Both, "Not recipient");
        _;
    }
    
    /**
     * @dev Register as a user
     */
    function registerUser(UserType _type, string calldata _name) external {
        require(_type != UserType.None, "Invalid type");
        require(users[msg.sender].userType == UserType.None, "Already registered");
        
        users[msg.sender].userType = _type;
        users[msg.sender].reputation = 100;
        userNames[msg.sender] = _name;
        
        emit UserRegistered(msg.sender, _type);
    }
    
    /**
     * @dev List a food item
     */
    function listItem(
        string calldata _name,
        uint256 _quantity,
        uint256 _hours,
        uint256 _price,
        string calldata _location
    ) external onlyRegistered canSupply {
        require(_quantity > 0, "Invalid quantity");
        require(_hours > 0, "Invalid hours");
        
        uint256 id = itemCount;
        
        items[id].supplier = msg.sender;
        items[id].quantity = _quantity;
        items[id].expiryTime = block.timestamp + (_hours * 1 hours);
        items[id].price = _price;
        items[id].status = Status.Available;
        
        itemNames[id] = _name;
        itemLocations[id] = _location;
        
        users[msg.sender].itemsListed++;
        itemCount++;
        totalItemsListed++;
        
        emit ItemListed(id, msg.sender);
    }
    
    /**
     * @dev Reserve an item
     */
    function reserveItem(uint256 _id) external payable onlyRegistered canReceive {
        require(_id < itemCount, "Item not found");
        
        FoodItem storage item = items[_id];
        require(item.status == Status.Available, "Not available");
        require(block.timestamp < item.expiryTime, "Expired");
        require(item.supplier != msg.sender, "Own item");
        require(msg.value >= item.price, "Insufficient payment");
        
        item.status = Status.Reserved;
        item.recipient = msg.sender;
        
        // Handle payment
        if (msg.value > item.price) {
            payable(msg.sender).transfer(msg.value - item.price);
        }
        if (item.price > 0) {
            payable(item.supplier).transfer(item.price);
        }
        
        emit ItemReserved(_id, msg.sender);
    }
    
    /**
     * @dev Confirm collection
     */
    function confirmCollection(uint256 _id) external onlyRegistered {
        require(_id < itemCount, "Item not found");
        
        FoodItem storage item = items[_id];
        require(item.status == Status.Reserved, "Not reserved");
        require(msg.sender == item.recipient || msg.sender == item.supplier, "Not authorized");
        
        item.status = Status.Collected;
        
        users[item.recipient].itemsReceived++;
        users[item.recipient].wasteSaved += item.quantity;
        totalWasteSaved += item.quantity;
        
        // Update reputation
        users[item.supplier].reputation += 5;
        users[item.recipient].reputation += 5;
        
        emit ItemCollected(_id);
    }
    
    // Simple view functions
    
    function getItem(uint256 _id) external view returns (
        address supplier,
        uint256 quantity,
        uint256 expiryTime,
        uint256 price,
        Status status
    ) {
        require(_id < itemCount, "Item not found");
        FoodItem storage item = items[_id];
        return (item.supplier, item.quantity, item.expiryTime, item.price, item.status);
    }
    
    function getItemName(uint256 _id) external view returns (string memory) {
        require(_id < itemCount, "Item not found");
        return itemNames[_id];
    }
    
    function getItemLocation(uint256 _id) external view returns (string memory) {
        require(_id < itemCount, "Item not found");
        return itemLocations[_id];
    }
    
    function getUser(address _user) external view returns (
        UserType userType,
        uint256 itemsListed,
        uint256 itemsReceived,
        uint256 reputation
    ) {
        User storage user = users[_user];
        return (user.userType, user.itemsListed, user.itemsReceived, user.reputation);
    }
    
    function getUserName(address _user) external view returns (string memory) {
        return userNames[_user];
    }
    
    function getStats() external view returns (
        uint256 _totalWasteSaved,
        uint256 _totalItemsListed,
        uint256 _itemCount
    ) {
        return (totalWasteSaved, totalItemsListed, itemCount);
    }
    
    function getAvailableCount() external view returns (uint256 count) {
        for (uint256 i = 0; i < itemCount; i++) {
            if (items[i].status == Status.Available && block.timestamp < items[i].expiryTime) {
                count++;
            }
        }
    }
    
    function isActive(uint256 _id) external view returns (bool) {
        require(_id < itemCount, "Item not found");
        return items[_id].status == Status.Available && block.timestamp < items[_id].expiryTime;
    }
    
    function markExpired(uint256 _id) external {
        require(_id < itemCount, "Item not found");
        FoodItem storage item = items[_id];
        require(block.timestamp >= item.expiryTime, "Not expired yet");
        require(item.status != Status.Collected, "Already collected");
        
        if (item.status == Status.Reserved && item.recipient != address(0)) {
            if (users[item.recipient].reputation >= 10) {
                users[item.recipient].reputation -= 10;
            }
        }
        
        item.status = Status.Expired;
    }
}
