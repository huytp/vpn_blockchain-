// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title NodeRegistry
 * @dev Quản lý đăng ký và trạng thái của VPN nodes
 */
contract NodeRegistry {
    struct Node {
        address operator;
        bool active;
    }

    mapping(address => Node) public nodes;
    address[] public nodeList;

    event NodeRegistered(address indexed node, address indexed operator);
    event NodeDisabled(address indexed node);

    /**
     * @dev Đăng ký node mới
     */
    function registerNode() external {
        require(!nodes[msg.sender].active, "Node already registered");

        nodes[msg.sender] = Node({
            operator: msg.sender,
            active: true
        });

        nodeList.push(msg.sender);
        emit NodeRegistered(msg.sender, msg.sender);
    }

    /**
     * @dev Vô hiệu hóa node
     */
    function disableNode(address node) external {
        require(nodes[node].active, "Node not active");
        nodes[node].active = false;
        emit NodeDisabled(node);
    }

    /**
     * @dev Kiểm tra node có active không
     */
    function isActive(address node) external view returns (bool) {
        return nodes[node].active;
    }
}

