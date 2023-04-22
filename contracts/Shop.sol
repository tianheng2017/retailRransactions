// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract Shop {
    // 买家信息结构体
    struct UserProfile {
        // 姓名
        string name;
        // 邮箱
        string email;
        // 收货地址
        string shippingAddress;
    }

    // 产品信息结构体
    struct Product {
        // 名称
        string name;
        // 价格
        uint256 price;
        // 库存
        uint256 stock;
    }

    // 交易信息结构体
    struct Transaction {
        // 购买人
        address buyer;
        // 产品ID
        uint256 productId;
        // 数量
        uint256 quantity;
        // 总价
        uint256 totalCost;
        // 订单是否完成
        bool isCompleted;
        // 是否申请退货
        bool returnRequested;
        // 退货是否批准
        bool returnApproved;
        // 买家申请退货时间
        uint256 returnRequestedTimestamp;
        // 评分
        uint256 rating;
    }

    address public seller;
    mapping(address => UserProfile) private users;
    mapping(uint256 => Product) public products;
    mapping(uint256 => Transaction) private transactions;
    uint256 public productCounter;
    uint256 public transactionCounter;
    uint256 public returnRequestTimeout = 7 days;
    
    modifier onlySeller() {
        require(msg.sender == seller, "Only seller can call this function.");
        _;
    }

    // 注册卖家
    constructor() payable {
        require(msg.value == 10 ether, "10 Ether deposit required.");
        seller = msg.sender;
    }

    // 注册买家
    function registerBuyer(
        string memory _name,
        string memory _email,
        string memory _shippingAddress
    ) public {
        require(msg.sender != seller, "Seller cannot be a buyer.");
        require(bytes(users[msg.sender].name).length == 0, "Address already registered.");
        users[msg.sender] = UserProfile(_name, _email, _shippingAddress);
    }

    // 买家查看个人资料
    function viewProfile() public view returns (string memory, string memory, string memory) {
        UserProfile storage buyer = users[msg.sender];

        // 确保调用者已经注册
        require(bytes(buyer.name).length > 0, "Caller is not registered.");
        return (
            buyer.name,
            buyer.email,
            buyer.shippingAddress
        );
    }

    // 添加产品
    // 只能由卖家操作
    function addProduct(string memory _name, uint256 _price, uint256 _stock) public onlySeller {
        productCounter++;
        products[productCounter] = Product(_name, _price, _stock);
    }

    // 查看交易信息
    // 卖家可以查看所有交易
    // 买家只能查看自己交易
    function viewTransaction(uint256 _transactionId) 
        public 
        view 
        returns (uint256, address, uint256, uint256, bool, bool, bool) 
    {
        Transaction storage txn = transactions[_transactionId];

        require(
            msg.sender == txn.buyer || msg.sender == seller,
            "Caller must be the buyer or the seller."
        );

        if (msg.sender != seller) {
            require(msg.sender == txn.buyer, "Buyer can only view their own transactions.");
        }

        return (
            txn.productId,
            txn.buyer,
            txn.quantity,
            txn.totalCost,
            txn.isCompleted,
            txn.returnRequested,
            txn.returnApproved
        );
    }

    // 买家发起交易
    function initiateTransaction(uint256 _productId, uint256 _quantity) public payable {
        require(_quantity > 0, "Quantity must be greater than 0.");
        require(products[_productId].stock >= _quantity, "Not enough stock available.");
        require(bytes(users[msg.sender].name).length != 0, "User not registered.");

        uint256 totalCost = products[_productId].price * _quantity;
        require(msg.value >= totalCost, "Insufficient funds.");

        transactionCounter++;
        transactions[transactionCounter] = Transaction(
            msg.sender,
            _productId,
            _quantity,
            totalCost,
            false,
            false,
            false,
            0,
            0
        );

        // 更新库存
        products[_productId].stock -= _quantity;
    }

    // 买家申请完成交易
    function completeTransaction(uint256 _transactionId) public {
        Transaction storage txn = transactions[_transactionId];

        require(msg.sender == txn.buyer, "Only buyer can complete the transaction.");
        require(!txn.isCompleted, "Transaction already completed.");

        txn.isCompleted = true;
        payable(seller).transfer(txn.totalCost);
    }

    // 买家请求退货
    function requestReturn(uint256 _transactionId) public {
        Transaction storage txn = transactions[_transactionId];

        require(msg.sender == txn.buyer, "Only buyer can request a return.");
        require(!txn.isCompleted, "Transaction already completed.");
        require(!txn.returnRequested, "Return already requested.");

        txn.returnRequested = true;
        txn.returnRequestedTimestamp = block.timestamp;
    }

    // 卖家获取待退货ID列表
    function getPendingReturnTransactions() public view onlySeller returns (uint256[] memory) {
        uint256 pendingReturnsCount = 0;

        for (uint256 i = 1; i <= transactionCounter; i++) {
            Transaction storage txn = transactions[i];
            if (txn.returnRequested && !txn.returnApproved && !txn.isCompleted) {
                pendingReturnsCount++;
            }
        }

        uint256[] memory pendingReturnIds = new uint256[](pendingReturnsCount);

        uint256 currentIndex = 0;
        for (uint256 i = 1; i <= transactionCounter; i++) {
            Transaction storage txn = transactions[i];
            if (txn.returnRequested && !txn.returnApproved && !txn.isCompleted) {
                pendingReturnIds[currentIndex] = i;
                currentIndex++;
            }
        }

        // 返回包含待退货交易ID的数组
        return pendingReturnIds;
    }

    // 卖家批准退货
    function approveReturn(uint256 _transactionId) public onlySeller {
        Transaction storage txn = transactions[_transactionId];

        require(txn.returnRequested, "No return requested.");
        require(!txn.isCompleted, "Transaction already completed.");
        require(!txn.returnApproved, "Return already approved.");

        txn.returnApproved = true;
        products[txn.productId].stock += txn.quantity;
        // 退款给买家
        payable(txn.buyer).transfer(txn.totalCost);

        penalizeSeller();
    }

    // 买家更新用户配置文件
    function updateProfile(
        string memory _name,
        string memory _email,
        string memory _shippingAddress
    ) public {
        require(bytes(users[msg.sender].name).length != 0, "User not registered.");
        users[msg.sender] = UserProfile(_name, _email, _shippingAddress);
    }

    // 买家评分
    function rateProduct(uint256 _transactionId, uint256 _rating) public {
        require(_rating >= 0 && _rating <= 5, "Rating must be between 0 and 5.");
        Transaction storage txn = transactions[_transactionId];
        require(msg.sender == txn.buyer, "Only buyer can rate the product.");
        require(txn.isCompleted, "Transaction must be completed.");
        txn.rating = _rating;
    }

    // 买家购买多个产品
    function initiateMultipleTransactions(uint256[] memory _productIds, uint256[] memory _quantities) public payable {
        require(_productIds.length == _quantities.length, "Product IDs and quantities must have the same length.");
        uint256 totalCost;

        for (uint256 i = 0; i < _productIds.length; i++) {
            uint256 productId = _productIds[i];
            uint256 quantity = _quantities[i];
            require(quantity > 0, "Quantity must be greater than 0.");
            require(products[productId].stock >= quantity, "Not enough stock available.");
            totalCost += products[productId].price * quantity;
        }

        require(msg.value >= totalCost, "Insufficient funds.");
        for (uint256 i = 0; i < _productIds.length; i++) {
            uint256 productId = _productIds[i];
            uint256 quantity = _quantities[i];
            initiateTransaction(productId, quantity);
        }
    }

    // 卖家惩罚机制
	// 卖家卖家批准退货时触发
    function penalizeSeller() public onlySeller {
        for (uint256 i = 1; i <= transactionCounter; i++) {
            Transaction storage txn = transactions[i];
            if (
                // 订单已申请退货
                txn.returnRequested &&
                // 订单还没被批准
                !txn.returnApproved &&
                // 订单也还没完成
                !txn.isCompleted &&
                // 当前时间 - 申请退货时间 > 7天
                (block.timestamp - txn.returnRequestedTimestamp) > returnRequestTimeout
            ) {
                // 订单超时，超时一单罚款0.1 eth，将罚款奖励给买家
                payable(txn.buyer).transfer(0.1 ether);
                // 批准退货
                txn.returnApproved = true;
                // 库存增加
                products[txn.productId].stock += txn.quantity;
                // 退款给买家
                payable(txn.buyer).transfer(txn.totalCost);
            }
        }
    }
}