// ========================================
// Dashboard Page Logic - Material Design
// ========================================

let currentOrders = [];
let selectedOrderId = null;
let modalInstance = null;

// Initialize
document.addEventListener('DOMContentLoaded', async () => {
    // Initialize Materialize components
    M.AutoInit();

    // Initialize modal
    const modalElem = document.getElementById('actionModal');
    modalInstance = M.Modal.init(modalElem);

    // Load data
    await loadStatistics();
    await loadUsers();
    await loadOrders();

    // Event listeners
    document.getElementById('filterStatus').addEventListener('change', applyFilters);
});

/**
 * 사용자 목록 로드
 */
async function loadUsers() {
    try {
        const users = await getUsers({ page: 1, limit: 100 });
        renderUserSelect(users);
    } catch (error) {
        console.error('Failed to load users:', error);
        M.toast({
            html: '<i class="material-icons left">error</i>사용자 목록 로드 실패',
            classes: 'red darken-2'
        });
    }
}

/**
 * 사용자 select 렌더링
 */
function renderUserSelect(users) {
    const selectContainer = document.getElementById('userSelectContainer');
    if (!selectContainer) return;

    if (!users || users.length === 0) {
        selectContainer.innerHTML = `
            <div class="input-field">
                <i class="material-icons prefix">person</i>
                <select id="filterUserSelect" disabled>
                    <option value="">사용자 없음</option>
                </select>
                <label>사용자 선택</label>
            </div>
        `;
        M.FormSelect.init(selectContainer.querySelectorAll('select'));
        return;
    }

    let html = `
        <div class="input-field">
            <i class="material-icons prefix">person</i>
            <select id="filterUserSelect">
                <option value="">전체 사용자</option>
    `;

    users.forEach(user => {
        html += `<option value="${user.id}">${user.username} (${user.email})</option>`;
    });

    html += `
            </select>
            <label>사용자 선택</label>
        </div>
    `;

    selectContainer.innerHTML = html;

    // Materialize select 초기화
    const selects = selectContainer.querySelectorAll('select');
    M.FormSelect.init(selects);

    // 사용자 선택 시 자동으로 사용자 ID 필드에 반영
    document.getElementById('filterUserSelect').addEventListener('change', function() {
        const userId = this.value;
        document.getElementById('filterUserId').value = userId;
        M.updateTextFields();
    });
}

/**
 * Load and display statistics
 */
async function loadStatistics() {
    try {
        const stats = await getOrderStatistics();
        displayStatistics(stats);
    } catch (error) {
        console.error('Failed to load statistics:', error);
        document.getElementById('statsGrid').innerHTML = `
            <div class="col s12">
                <div class="card red lighten-4">
                    <div class="card-content red-text text-darken-4">
                        <i class="material-icons left">error</i>
                        통계 로드 실패. API 서버를 확인해주세요.
                    </div>
                </div>
            </div>
        `;
    }
}

/**
 * Display statistics on page
 */
function displayStatistics(stats) {
    const statsGrid = document.getElementById('statsGrid');
    const { totalOrders, totalRevenue, statusBreakdown } = stats;

    let html = `
        <div class="col s12 m6 l3">
            <div class="card stat-card blue darken-2">
                <i class="material-icons stat-icon">shopping_basket</i>
                <div class="stat-label">총 주문 건수</div>
                <div class="stat-value">${totalOrders}</div>
            </div>
        </div>

        <div class="col s12 m6 l3">
            <div class="card stat-card green darken-1">
                <i class="material-icons stat-icon">attach_money</i>
                <div class="stat-label">총 매출</div>
                <div class="stat-value">${formatCurrency(totalRevenue)}</div>
            </div>
        </div>
    `;

    if (statusBreakdown && statusBreakdown.length > 0) {
        const statusColors = {
            'COMPLETED': 'teal darken-1',
            'CANCELLED': 'red darken-1',
            'PROCESSING': 'orange darken-1',
            'PENDING': 'blue-grey darken-1'
        };

        const statusIcons = {
            'COMPLETED': 'check_circle',
            'CANCELLED': 'cancel',
            'PROCESSING': 'autorenew',
            'PENDING': 'schedule'
        };

        statusBreakdown.forEach((status) => {
            const colorClass = statusColors[status.status] || 'grey darken-1';
            const icon = statusIcons[status.status] || 'info';

            html += `
                <div class="col s12 m6 l3">
                    <div class="card stat-card ${colorClass}">
                        <i class="material-icons stat-icon">${icon}</i>
                        <div class="stat-label">${getStatusLabel(status.status)}</div>
                        <div class="stat-value">${status.count}</div>
                    </div>
                </div>
            `;
        });
    }

    statsGrid.innerHTML = html;
}

/**
 * Load and display orders
 */
async function loadOrders() {
    try {
        const filters = getFilterValues();
        const orders = await getOrders(filters);

        currentOrders = orders.data || [];
        displayOrders(currentOrders);
    } catch (error) {
        console.error('Failed to load orders:', error);
        document.getElementById('ordersContainer').innerHTML = `
            <div class="card red lighten-4">
                <div class="card-content red-text text-darken-4">
                    <i class="material-icons left">error</i>
                    주문 데이터 로드 실패. API 서버를 확인해주세요.
                </div>
            </div>
        `;
    }
}

/**
 * Display orders in table
 */
function displayOrders(orders) {
    const container = document.getElementById('ordersContainer');

    if (!orders || orders.length === 0) {
        container.innerHTML = `
            <div class="center-align grey-text" style="padding: 40px 0;">
                <i class="material-icons" style="font-size: 64px; opacity: 0.3;">inbox</i>
                <h5>주문이 없습니다</h5>
                <p>새 주문을 생성해주세요.</p>
                <a href="/orders.html" class="btn waves-effect waves-light blue darken-2" style="margin-top: 20px;">
                    <i class="material-icons left">add_shopping_cart</i>주문 생성하기
                </a>
            </div>
        `;
        return;
    }

    let html = `
        <table class="striped highlight responsive-table">
            <thead>
                <tr>
                    <th>주문 ID</th>
                    <th>사용자 ID</th>
                    <th>상태</th>
                    <th>총액</th>
                    <th>주문일시</th>
                    <th>상품 수</th>
                    <th>작업</th>
                </tr>
            </thead>
            <tbody>
    `;

    orders.forEach((order) => {
        const itemCount = order.items ? order.items.length : 0;
        const statusColors = {
            'PENDING': 'orange lighten-4 orange-text text-darken-3',
            'PROCESSING': 'blue lighten-4 blue-text text-darken-3',
            'COMPLETED': 'green lighten-4 green-text text-darken-3',
            'CANCELLED': 'red lighten-4 red-text text-darken-3'
        };

        html += `
            <tr>
                <td><strong>#${order.id}</strong></td>
                <td><i class="material-icons tiny">person</i> ${order.userId}</td>
                <td>
                    <span class="status-chip ${statusColors[order.status] || ''}">
                        ${getStatusLabel(order.status)}
                    </span>
                </td>
                <td><strong>${formatCurrency(order.totalAmount)}</strong></td>
                <td><i class="material-icons tiny">schedule</i> ${formatDate(order.orderDate)}</td>
                <td><span class="badge blue white-text">${itemCount}</span></td>
                <td>
                    <a class="btn-small waves-effect waves-light blue darken-1" onclick="viewOrderDetails(${order.id})">
                        <i class="material-icons left">visibility</i>상세
                    </a>
                    ${order.status !== 'COMPLETED' && order.status !== 'CANCELLED' ?
                        `<a class="btn-small waves-effect waves-light orange darken-1" onclick="openStatusModal(${order.id})" style="margin-left: 5px;">
                            <i class="material-icons left">edit</i>상태
                        </a>` : ''}
                    ${order.status !== 'CANCELLED' && order.status !== 'COMPLETED' ?
                        `<a class="btn-small waves-effect waves-light red darken-1" onclick="cancelOrderConfirm(${order.id})" style="margin-left: 5px;">
                            <i class="material-icons left">cancel</i>취소
                        </a>` : ''}
                </td>
            </tr>
        `;

        // Add items details
        if (order.items && order.items.length > 0) {
            html += '<tr style="background-color: #f5f5f5;"><td colspan="7">';
            html += '<div style="padding: 10px;"><strong><i class="material-icons tiny">inventory</i> 주문 항목:</strong>';
            html += '<ul class="collection" style="margin-top: 10px; border: none;">';
            order.items.forEach((item) => {
                html += `
                    <li class="collection-item" style="border: none; padding: 5px 0;">
                        <i class="material-icons tiny blue-text">shopping_bag</i>
                        ${item.productName} <span class="grey-text">x${item.quantity}</span>
                        <span class="right"><strong>${formatCurrency(item.subtotal)}</strong></span>
                    </li>
                `;
            });
            html += '</ul></div></td></tr>';
        }
    });

    html += `
            </tbody>
        </table>
    `;

    container.innerHTML = html;
}

/**
 * Get filter values from form
 */
function getFilterValues() {
    const filters = {};

    const status = document.getElementById('filterStatus').value;
    if (status) filters.status = status;

    const userId = document.getElementById('filterUserId').value;
    if (userId) filters.userId = userId;

    return filters;
}

/**
 * Apply filters and reload orders
 */
function applyFilters() {
    M.toast({
        html: '<i class="material-icons left">filter_list</i>필터 적용 중...',
        classes: 'blue darken-2'
    });
    loadOrders();
}

/**
 * Reset filters
 */
function resetFilters() {
    document.getElementById('filterStatus').value = '';
    document.getElementById('filterUserId').value = '';

    const userSelect = document.getElementById('filterUserSelect');
    if (userSelect) {
        userSelect.value = '';
    }

    // Reinitialize select
    const selects = document.querySelectorAll('select');
    M.FormSelect.init(selects);

    // Update text fields
    M.updateTextFields();

    M.toast({
        html: '<i class="material-icons left">refresh</i>필터가 초기화되었습니다',
        classes: 'grey'
    });

    loadOrders();
}

/**
 * View order details
 */
async function viewOrderDetails(orderId) {
    try {
        const order = await getOrderById(orderId);

        let html = `
            <h5><i class="material-icons left blue-text">receipt</i>주문 #${order.id}</h5>
            <div class="divider"></div>
            <ul class="collection" style="margin-top: 20px; border: none;">
                <li class="collection-item">
                    <i class="material-icons left tiny blue-text">person</i>
                    <strong>사용자 ID:</strong> ${order.userId}
                </li>
                <li class="collection-item">
                    <i class="material-icons left tiny blue-text">assignment</i>
                    <strong>상태:</strong> ${getStatusLabel(order.status)}
                </li>
                <li class="collection-item">
                    <i class="material-icons left tiny blue-text">attach_money</i>
                    <strong>총액:</strong> ${formatCurrency(order.totalAmount)}
                </li>
                <li class="collection-item">
                    <i class="material-icons left tiny blue-text">schedule</i>
                    <strong>주문일시:</strong> ${formatDate(order.orderDate)}
                </li>
            </ul>

            <h6><i class="material-icons left green-text">inventory</i>주문 항목</h6>
            <div class="divider"></div>
            <ul class="collection" style="margin-top: 10px;">
        `;

        if (order.items && order.items.length > 0) {
            order.items.forEach((item, index) => {
                html += `
                    <li class="collection-item">
                        <div>
                            <strong>${index + 1}. ${item.productName}</strong>
                            <p class="grey-text">수량: ${item.quantity} × ${formatCurrency(item.price)}</p>
                            <span class="secondary-content blue-text"><strong>${formatCurrency(item.subtotal)}</strong></span>
                        </div>
                    </li>
                `;
            });
        }

        html += '</ul>';

        // Create modal for details
        const detailsDiv = document.createElement('div');
        detailsDiv.innerHTML = `
            <div id="detailsModal" class="modal">
                <div class="modal-content">
                    ${html}
                </div>
                <div class="modal-footer">
                    <a class="modal-close waves-effect waves-light btn-flat">닫기</a>
                </div>
            </div>
        `;

        document.body.appendChild(detailsDiv);
        const detailsModal = M.Modal.init(document.getElementById('detailsModal'));
        detailsModal.open();

        // Remove modal on close
        detailsModal.options.onCloseEnd = function() {
            detailsDiv.remove();
        };

    } catch (error) {
        M.toast({
            html: `<i class="material-icons left">error</i>${error.message}`,
            classes: 'red darken-2'
        });
    }
}

/**
 * Open status change modal
 */
function openStatusModal(orderId) {
    selectedOrderId = orderId;
    modalInstance.open();

    // Reinitialize select in modal
    setTimeout(() => {
        const selects = document.querySelectorAll('#actionModal select');
        M.FormSelect.init(selects);
    }, 100);
}

/**
 * Confirm and apply status change
 */
async function confirmStatusChange() {
    if (!selectedOrderId) return;

    try {
        const newStatus = document.getElementById('newStatus').value;
        await updateOrder(selectedOrderId, { status: newStatus });

        modalInstance.close();

        M.toast({
            html: '<i class="material-icons left">check_circle</i>주문 상태가 업데이트되었습니다',
            classes: 'green darken-1'
        });

        await loadOrders();
        await loadStatistics();

        selectedOrderId = null;
    } catch (error) {
        M.toast({
            html: `<i class="material-icons left">error</i>${error.message}`,
            classes: 'red darken-2'
        });
    }
}

/**
 * Cancel order with confirmation
 */
async function cancelOrderConfirm(orderId) {
    // Create confirmation modal
    const confirmDiv = document.createElement('div');
    confirmDiv.innerHTML = `
        <div id="confirmModal" class="modal">
            <div class="modal-content">
                <h5><i class="material-icons left orange-text">warning</i>주문 취소 확인</h5>
                <p>이 주문을 취소하시겠습니까?</p>
            </div>
            <div class="modal-footer">
                <a class="modal-close waves-effect waves-light btn-flat">아니오</a>
                <a class="waves-effect waves-light btn red darken-1" onclick="executeCancelOrder(${orderId})">
                    <i class="material-icons left">cancel</i>예, 취소합니다
                </a>
            </div>
        </div>
    `;

    document.body.appendChild(confirmDiv);
    const confirmModal = M.Modal.init(document.getElementById('confirmModal'));
    confirmModal.open();

    // Remove modal on close
    confirmModal.options.onCloseEnd = function() {
        confirmDiv.remove();
    };
}

/**
 * Execute order cancellation
 */
async function executeCancelOrder(orderId) {
    try {
        // Close confirmation modal
        const confirmModal = M.Modal.getInstance(document.getElementById('confirmModal'));
        confirmModal.close();

        await cancelOrder(orderId);

        M.toast({
            html: '<i class="material-icons left">check_circle</i>주문이 취소되었습니다',
            classes: 'orange darken-1'
        });

        await loadOrders();
        await loadStatistics();
    } catch (error) {
        M.toast({
            html: `<i class="material-icons left">error</i>${error.message}`,
            classes: 'red darken-2'
        });
    }
}
