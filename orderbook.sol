// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IERC20 {
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

contract OrderBook {
    struct Order {
        uint256 id;
        address trader;
        uint256 amount;   // Amount of tokens
        uint256 price;    // Price per token in base currency
        bool isBuy;       // True for buy order, false for sell order
        bool isActive;    // Whether the order is still active
    }

    uint256 public orderCount; // Unique ID for each order
    mapping(uint256 => Order) public orders; // Store orders by ID

    // Order book (separate arrays for buy and sell orders)
    uint256[] public buyOrders;
    uint256[] public sellOrders;

    address public token; // Token being traded
    address public baseToken; // Base token (e.g., USDT)

    event OrderPlaced(uint256 id, address trader, uint256 amount, uint256 price, bool isBuy);
    event OrderMatched(uint256 buyOrderId, uint256 sellOrderId, uint256 amount, uint256 price);
    event OrderCancelled(uint256 id);

    constructor(address _token, address _baseToken) {
        token = _token;
        baseToken = _baseToken;
    }

    // Place an order (buy or sell)
    function placeOrder(uint256 amount, uint256 price, bool isBuy) external {
        require(amount > 0, "Amount must be greater than zero");
        require(price > 0, "Price must be greater than zero");

        // Ensure the trader has enough tokens (for sell orders) or base tokens (for buy orders)
        if (isBuy) {
            require(IERC20(baseToken).balanceOf(msg.sender) >= amount * price, "Insufficient base token balance");
        } else {
            require(IERC20(token).balanceOf(msg.sender) >= amount, "Insufficient token balance");
        }

        // Create the order
        orders[orderCount] = Order(orderCount, msg.sender, amount, price, isBuy, true);

        // Add to the appropriate order book
        if (isBuy) {
            buyOrders.push(orderCount);
        } else {
            sellOrders.push(orderCount);
        }

        emit OrderPlaced(orderCount, msg.sender, amount, price, isBuy);

        // Match orders
        matchOrders();

        orderCount++;
    }

    // Match orders
    function matchOrders() internal {
        uint256 i = 0; // Pointer for buy orders
        uint256 j = 0; // Pointer for sell orders

        while (i < buyOrders.length && j < sellOrders.length) {
            Order storage buyOrder = orders[buyOrders[i]];
            Order storage sellOrder = orders[sellOrders[j]];

            // Skip inactive orders
            if (!buyOrder.isActive) {
                i++;
                continue;
            }
            if (!sellOrder.isActive) {
                j++;
                continue;
            }

            // Match if the buy price is >= the sell price
            if (buyOrder.price >= sellOrder.price) {
                uint256 tradeAmount = min(buyOrder.amount, sellOrder.amount);
                uint256 tradePrice = sellOrder.price;

                // Execute the trade
                executeTrade(buyOrder, sellOrder, tradeAmount, tradePrice);

                // Update order amounts
                buyOrder.amount -= tradeAmount;
                sellOrder.amount -= tradeAmount;

                // Deactivate orders if fully matched
                if (buyOrder.amount == 0) buyOrder.isActive = false;
                if (sellOrder.amount == 0) sellOrder.isActive = false;

                // Remove fully matched orders from the arrays
                if (!buyOrder.isActive) i++;
                if (!sellOrder.isActive) j++;
            } else {
                // Break if no more matches are possible
                break;
            }
        }
    }

    // Execute a trade
    function executeTrade(Order storage buyOrder, Order storage sellOrder, uint256 tradeAmount, uint256 tradePrice) internal {
        uint256 cost = tradeAmount * tradePrice;

        // Transfer base tokens from buyer to seller
        require(IERC20(baseToken).transferFrom(buyOrder.trader, sellOrder.trader, cost), "Base token transfer failed");

        // Transfer tokens from seller to buyer
        require(IERC20(token).transferFrom(sellOrder.trader, buyOrder.trader, tradeAmount), "Token transfer failed");

        emit OrderMatched(buyOrder.id, sellOrder.id, tradeAmount, tradePrice);
    }

    // Cancel an order
    function cancelOrder(uint256 orderId) external {
        Order storage order = orders[orderId];
        require(order.trader == msg.sender, "Not your order");
        require(order.isActive, "Order already inactive");

        order.isActive = false;

        emit OrderCancelled(orderId);
    }

    // Helper function to get the minimum of two numbers
    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }

    // Get all active buy orders
    function getActiveBuyOrders() external view returns (uint256[] memory) {
        return filterActiveOrders(buyOrders);
    }

    // Get all active sell orders
    function getActiveSellOrders() external view returns (uint256[] memory) {
        return filterActiveOrders(sellOrders);
    }

    // Helper to filter active orders
    function filterActiveOrders(uint256[] memory orderArray) internal view returns (uint256[] memory) {
        uint256[] memory activeOrders = new uint256[](orderArray.length);
        uint256 count = 0;

        for (uint256 i = 0; i < orderArray.length; i++) {
            if (orders[orderArray[i]].isActive) {
                activeOrders[count] = orderArray[i];
                count++;
            }
        }

        // Resize the array to the correct size
        bytes memory resizedArray = abi.encodePacked(activeOrders);
        assembly { mstore(resizedArray, count) }
        return abi.decode(resizedArray, (uint256[]));
    }
}