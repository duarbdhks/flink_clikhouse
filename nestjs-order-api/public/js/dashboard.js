// ========================================
// Dashboard Page Logic
// ========================================

let currentOrders = [];
let selectedOrderId = null;

// Initialize
document.addEventListener('DOMContentLoaded', async () => {
    await loadStatistics();
    await loadOrders();

    // Event listeners
    document.getElementById('filterStatus').addEventListener('change', applyFilters);
});

/**
 * Load and display statistics
 */
async function loadStatistics() {
    try {
        const stats = await getOrderStatistics();
        displayStatistics(stats);
    } catch (error) {
        console.error('Failed to load statistics:', error);
        document.getElementById('statsGrid').innerHTML =
            '<div class="alert alert-error">통계 로드 실패. API 서버를 확인해주세요.</div>';
    }
}

/**
 * Display statistics on page
 */
function displayStatistics(stats) {
    const statsGrid = document.getElementById('statsGrid');
    const { totalOrders, totalRevenue, statusBreakdown } = stats;

    let html = `
        <div class="stat-card">
            <div class="stat-label">총 주문 건수</div>
            <div class="stat-value">${totalOrders}</div>
        </div>
        <div class="stat-card success">
            <div class="stat-label">총 매출</div>
            <div class="stat-value">${formatCurrency(totalRevenue)}</div>
        </div>
    `;

    if (statusBreakdown && statusBreakdown.length > 0) {
        statusBreakdown.forEach((status) => {
            let cardClass = 'stat-card';
            if (status.status === 'COMPLETED') cardClass += ' success';
            else if (status.status === 'CANCELLED') cardClass += ' danger';
            else if (status.status === 'PROCESSING') cardClass += ' warning';

            html += `
                <div class="${cardClass}">
                    <div class="stat-label">${getStatusLabel(status.status)}</div>
                    <div class="stat-value">${status.count}</div>
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
        document.getElementById('ordersContainer').innerHTML =
            '<div class="alert alert-error">주문 데이터 로드 실패. API 서버를 확인해주세요.</div>';
    }
}

/**
 * Display orders in table
 */
function displayOrders(orders) {
    const container = document.getElementById('ordersContainer');

    if (!orders || orders.length === 0) {
        container.innerHTML = '<div class="empty-state"><h3>주문이 없습니다</h3><p>새 주문을 생성해주세요.</p></div>';
        return;
    }

    let html = `
        <table>
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
        html += `
            <tr>
                <td><strong>#${order.id}</strong></td>
                <td>${order.userId}</td>
                <td>
                    <span class="status-badge ${getStatusBadgeClass(order.status)}">
                        ${getStatusLabel(order.status)}
                    </span>
                </td>
                <td>${formatCurrency(order.totalAmount)}</td>
                <td>${formatDate(order.orderDate)}</td>
                <td>${itemCount}</td>
                <td>
                    <button class="btn btn-sm btn-info" onclick="viewOrderDetails(${order.id})">
                        상세보기
                    </button>
                    ${order.status !== 'COMPLETED' && order.status !== 'CANCELLED' ?
                        `<button class="btn btn-sm btn-warning" onclick="openStatusModal(${order.id})">
                            상태변경
                        </button>` : ''}
                    ${order.status !== 'CANCELLED' && order.status !== 'COMPLETED' ?
                        `<button class="btn btn-sm btn-danger" onclick="cancelOrderConfirm(${order.id})">
                            취소
                        </button>` : ''}
                </td>
            </tr>
        `;

        // Add items details
        if (order.items && order.items.length > 0) {
            html += '<tr style="background-color: #f9f9f9;"><td colspan="7">';
            html += '<strong>📦 주문 항목:</strong><ul style="margin: 10px 0; padding-left: 20px;">';
            order.items.forEach((item) => {
                html += `<li>${item.productName} x${item.quantity} = ${formatCurrency(item.subtotal)}</li>`;
            });
            html += '</ul></td></tr>';
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
    loadOrders();
}

/**
 * Reset filters
 */
function resetFilters() {
    document.getElementById('filterStatus').value = '';
    document.getElementById('filterUserId').value = '';
    loadOrders();
}

/**
 * View order details
 */
async function viewOrderDetails(orderId) {
    try {
        const order = await getOrderById(orderId);
        let details = `주문 #${order.id}\n\n`;
        details += `사용자 ID: ${order.userId}\n`;
        details += `상태: ${getStatusLabel(order.status)}\n`;
        details += `총액: ${formatCurrency(order.totalAmount)}\n`;
        details += `주문일시: ${formatDate(order.orderDate)}\n\n`;
        details += `📦 주문 항목:\n`;

        if (order.items && order.items.length > 0) {
            order.items.forEach((item, index) => {
                details += `${index + 1}. ${item.productName}\n`;
                details += `   수량: ${item.quantity}, 단가: ${formatCurrency(item.price)}\n`;
                details += `   소계: ${formatCurrency(item.subtotal)}\n`;
            });
        }

        alert(details);
    } catch (error) {
        showError(error.message);
    }
}

/**
 * Open status change modal
 */
function openStatusModal(orderId) {
    selectedOrderId = orderId;
    document.getElementById('actionModal').classList.remove('hidden');
}

/**
 * Close modal
 */
function closeModal() {
    document.getElementById('actionModal').classList.add('hidden');
    selectedOrderId = null;
}

/**
 * Confirm and apply status change
 */
async function confirmStatusChange() {
    if (!selectedOrderId) return;

    try {
        const newStatus = document.getElementById('newStatus').value;
        await updateOrder(selectedOrderId, { status: newStatus });
        closeModal();
        showSuccess('주문 상태가 업데이트되었습니다.');
        await loadOrders();
        await loadStatistics();
    } catch (error) {
        showError(error.message);
    }
}

/**
 * Cancel order with confirmation
 */
async function cancelOrderConfirm(orderId) {
    if (!confirm('이 주문을 취소하시겠습니까?')) return;

    try {
        await cancelOrder(orderId);
        showSuccess('주문이 취소되었습니다.');
        await loadOrders();
        await loadStatistics();
    } catch (error) {
        showError(error.message);
    }
}

/* ========================================
   Modal Styles (inline for simplicity)
   ======================================== */
const style = document.createElement('style');
style.textContent = `
    .modal {
        display: flex;
        position: fixed;
        z-index: 1000;
        left: 0;
        top: 0;
        width: 100%;
        height: 100%;
        background-color: rgba(0, 0, 0, 0.5);
        align-items: center;
        justify-content: center;
    }

    .modal.hidden {
        display: none;
    }

    .modal-content {
        background-color: white;
        padding: 30px;
        border-radius: 8px;
        box-shadow: 0 4px 20px rgba(0, 0, 0, 0.3);
        min-width: 300px;
        max-width: 500px;
    }

    .modal-content h3 {
        margin-top: 0;
        color: #3498db;
    }

    .modal-content button {
        margin-top: 15px;
        margin-right: 10px;
    }
`;
document.head.appendChild(style);
