// ========================================
// Order Creation Page Logic
// ========================================

let items = [];

// Initialize
document.addEventListener('DOMContentLoaded', () => {
    // Add initial empty item
    addItem();
    updateSummary();
});

/**
 * Add a new item row
 */
function addItem() {
    const itemId = items.length;
    const item = {
        id: itemId,
        productId: '',
        productName: '',
        quantity: 1,
        price: 0,
    };
    items.push(item);

    renderItems();
    updateSummary();
}

/**
 * Remove an item row
 */
function removeItem(itemId) {
    if (items.length <= 1) {
        showError('최소 1개 이상의 상품이 필요합니다.');
        return;
    }

    items = items.filter((item) => item.id !== itemId);
    renderItems();
    updateSummary();
}

/**
 * Render all item rows
 */
function renderItems() {
    const container = document.getElementById('itemsContainer');

    let html = '<div class="items-list">';

    items.forEach((item) => {
        html += `
            <div class="item-row" style="background: white; padding: 15px; border: 1px solid #bdc3c7; border-radius: 4px; margin-bottom: 10px;">
                <div class="form-row">
                    <div class="form-group">
                        <label>상품 ID</label>
                        <input type="number" placeholder="상품 ID" value="${item.productId}" min="1"
                            onchange="updateItem(${item.id}, 'productId', this.value)">
                    </div>
                    <div class="form-group">
                        <label>상품명</label>
                        <input type="text" placeholder="상품명 입력" value="${item.productName}"
                            onchange="updateItem(${item.id}, 'productName', this.value)">
                    </div>
                </div>
                <div class="form-row">
                    <div class="form-group">
                        <label>수량</label>
                        <input type="number" placeholder="수량" value="${item.quantity}" min="1"
                            onchange="updateItem(${item.id}, 'quantity', parseInt(this.value))">
                    </div>
                    <div class="form-group">
                        <label>단가 (₩)</label>
                        <input type="number" placeholder="단가" value="${item.price}" min="0"
                            onchange="updateItem(${item.id}, 'price', parseInt(this.value))">
                    </div>
                </div>
                <div style="display: flex; justify-content: space-between; align-items: center;">
                    <span style="font-weight: 600;">소계: ${formatCurrency(getItemSubtotal(item))}</span>
                    <button type="button" class="btn btn-sm btn-danger" onclick="removeItem(${item.id})">
                        🗑️ 삭제
                    </button>
                </div>
            </div>
        `;
    });

    html += '</div>';
    container.innerHTML = html;
}

/**
 * Update an item property
 */
function updateItem(itemId, property, value) {
    const item = items.find((i) => i.id === itemId);
    if (item) {
        item[property] = value;
        renderItems();
        updateSummary();
    }
}

/**
 * Get item subtotal
 */
function getItemSubtotal(item) {
    return item.quantity * item.price;
}

/**
 * Update summary (item count and total amount)
 */
function updateSummary() {
    const totalItems = items.reduce((sum, item) => sum + item.quantity, 0);
    const totalAmount = items.reduce((sum, item) => sum + getItemSubtotal(item), 0);

    document.getElementById('itemCount').textContent = totalItems;
    document.getElementById('totalAmount').textContent = formatCurrency(totalAmount);
}

/**
 * Validate order data
 */
function validateOrder() {
    const userId = document.getElementById('userId').value;

    // Validate userId
    if (!userId) {
        showError('사용자 ID를 입력해주세요.');
        return false;
    }

    if (isNaN(userId) || parseInt(userId) <= 0) {
        showError('유효한 사용자 ID를 입력해주세요.');
        return false;
    }

    // Validate items
    if (items.length === 0) {
        showError('최소 1개 이상의 상품이 필요합니다.');
        return false;
    }

    // Validate each item
    for (let i = 0; i < items.length; i++) {
        const item = items[i];

        if (!item.productId || isNaN(item.productId) || parseInt(item.productId) <= 0) {
            showError(`상품 ${i + 1}: 유효한 상품 ID를 입력해주세요.`);
            return false;
        }

        if (!item.productName || item.productName.trim() === '') {
            showError(`상품 ${i + 1}: 상품명을 입력해주세요.`);
            return false;
        }

        if (isNaN(item.quantity) || item.quantity <= 0) {
            showError(`상품 ${i + 1}: 수량은 1 이상이어야 합니다.`);
            return false;
        }

        if (isNaN(item.price) || item.price < 0) {
            showError(`상품 ${i + 1}: 유효한 단가를 입력해주세요.`);
            return false;
        }

        if (item.quantity * item.price === 0) {
            showError(`상품 ${i + 1}: 총액이 0이 될 수 없습니다.`);
            return false;
        }
    }

    return true;
}

/**
 * Build order data object
 */
function buildOrderData() {
    const userId = parseInt(document.getElementById('userId').value);

    const orderData = {
        userId,
        items: items.map((item) => ({
            productId: parseInt(item.productId),
            productName: item.productName,
            quantity: item.quantity,
            price: item.price,
        })),
    };

    return orderData;
}

/**
 * Submit order
 */
async function submitOrder() {
    // Validate
    if (!validateOrder()) {
        return;
    }

    try {
        const orderData = buildOrderData();

        // Show loading state
        const submitBtn = event.target;
        const originalText = submitBtn.textContent;
        submitBtn.disabled = true;
        submitBtn.textContent = '📤 주문 생성 중...';

        const response = await createOrder(orderData);

        showSuccess(`주문이 성공적으로 생성되었습니다! (주문 #${response.id})`);

        // Reset form after delay
        setTimeout(() => {
            document.getElementById('userId').value = '';
            items = [];
            addItem();
            updateSummary();
            submitBtn.disabled = false;
            submitBtn.textContent = originalText;
        }, 1500);
    } catch (error) {
        showError(error.message || '주문 생성에 실패했습니다. 다시 시도해주세요.');
    } finally {
        const submitBtn = event.target;
        if (submitBtn) {
            submitBtn.disabled = false;
            submitBtn.textContent = '✅ 주문 생성';
        }
    }
}

/**
 * Navigate to dashboard
 */
function goToDashboard() {
    window.location.href = '/dashboard.html';
}

/* ========================================
   Additional Styling for Order Form
   ======================================== */
const orderStyles = document.createElement('style');
orderStyles.textContent = `
    .items-list {
        margin-bottom: 20px;
    }

    .item-row {
        transition: all 0.3s ease;
    }

    .item-row:hover {
        box-shadow: 0 2px 8px rgba(0, 0, 0, 0.1);
    }

    .order-summary {
        background: linear-gradient(135deg, #ecf0f1 0%, #f8f9fa 100%);
        padding: 20px;
        border-radius: 8px;
        margin: 20px 0;
        border-left: 4px solid #3498db;
    }

    .summary-row {
        display: flex;
        justify-content: space-between;
        align-items: center;
        padding: 10px 0;
        font-size: 16px;
        font-weight: 600;
    }

    .summary-row:first-child {
        padding-top: 0;
    }

    .summary-row:last-child {
        padding-bottom: 0;
        border-top: 2px solid #bdc3c7;
        padding-top: 15px;
        margin-top: 10px;
        color: #27ae60;
        font-size: 18px;
    }
`;
document.head.appendChild(orderStyles);
