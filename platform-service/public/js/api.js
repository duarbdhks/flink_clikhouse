// ========================================
// API Helper Functions
// ========================================

const API_BASE_URL = '/api';

// ========================================
// Orders API
// ========================================

/**
 * 주문 목록 조회
 */
async function getOrders(params = {}) {
    try {
        const queryString = new URLSearchParams(params).toString();
        const url = `${API_BASE_URL}/orders${queryString ? '?' + queryString : ''}`;
        const response = await fetch(url);

        if (!response.ok) {
            throw new Error(`HTTP error! status: ${response.status}`);
        }

        const data = await response.json();
        return data;
    } catch (error) {
        console.error('Error fetching orders:', error);
        throw error;
    }
}

/**
 * 주문 상세 조회
 */
async function getOrderById(id) {
    try {
        const response = await fetch(`${API_BASE_URL}/orders/${id}`);

        if (!response.ok) {
            throw new Error(`HTTP error! status: ${response.status}`);
        }

        const data = await response.json();
        return data;
    } catch (error) {
        console.error(`Error fetching order ${id}:`, error);
        throw error;
    }
}

/**
 * 새 주문 생성
 */
async function createOrder(orderData) {
    try {
        const response = await fetch(`${API_BASE_URL}/orders`, {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
            },
            body: JSON.stringify(orderData),
        });

        if (!response.ok) {
            const error = await response.json();
            throw new Error(error.message || `HTTP error! status: ${response.status}`);
        }

        const data = await response.json();
        return data;
    } catch (error) {
        console.error('Error creating order:', error);
        throw error;
    }
}

/**
 * 주문 상태 업데이트
 */
async function updateOrder(id, updateData) {
    try {
        const response = await fetch(`${API_BASE_URL}/orders/${id}`, {
            method: 'PATCH',
            headers: {
                'Content-Type': 'application/json',
            },
            body: JSON.stringify(updateData),
        });

        if (!response.ok) {
            const error = await response.json();
            throw new Error(error.message || `HTTP error! status: ${response.status}`);
        }

        const data = await response.json();
        return data;
    } catch (error) {
        console.error(`Error updating order ${id}:`, error);
        throw error;
    }
}

/**
 * 주문 취소
 */
async function cancelOrder(id) {
    try {
        const response = await fetch(`${API_BASE_URL}/orders/${id}`, {
            method: 'DELETE',
        });

        if (!response.ok && response.status !== 204) {
            const error = await response.json();
            throw new Error(error.message || `HTTP error! status: ${response.status}`);
        }

        return { success: true };
    } catch (error) {
        console.error(`Error cancelling order ${id}:`, error);
        throw error;
    }
}

/**
 * 주문 통계 조회
 */
async function getOrderStatistics() {
    try {
        const response = await fetch(`${API_BASE_URL}/orders/statistics`);

        if (!response.ok) {
            throw new Error(`HTTP error! status: ${response.status}`);
        }

        const data = await response.json();
        return data;
    } catch (error) {
        console.error('Error fetching order statistics:', error);
        throw error;
    }
}

// ========================================
// Products API
// ========================================

/**
 * 상품 목록 조회
 */
async function getProducts(params = {}) {
    try {
        const queryString = new URLSearchParams(params).toString();
        const url = `${API_BASE_URL}/products${queryString ? '?' + queryString : ''}`;
        const response = await fetch(url);

        if (!response.ok) {
            throw new Error(`HTTP error! status: ${response.status}`);
        }

        const data = await response.json();
        return data;
    } catch (error) {
        console.error('Error fetching products:', error);
        throw error;
    }
}

/**
 * 상품 상세 조회
 */
async function getProductById(id) {
    try {
        const response = await fetch(`${API_BASE_URL}/products/${id}`);

        if (!response.ok) {
            throw new Error(`HTTP error! status: ${response.status}`);
        }

        const data = await response.json();
        return data;
    } catch (error) {
        console.error(`Error fetching product ${id}:`, error);
        throw error;
    }
}

// ========================================
// Users API
// ========================================

/**
 * 사용자 목록 조회
 */
async function getUsers(params = {}) {
    try {
        const queryString = new URLSearchParams(params).toString();
        const url = `${API_BASE_URL}/users${queryString ? '?' + queryString : ''}`;
        const response = await fetch(url);

        if (!response.ok) {
            throw new Error(`HTTP error! status: ${response.status}`);
        }

        const data = await response.json();
        return data;
    } catch (error) {
        console.error('Error fetching users:', error);
        throw error;
    }
}

/**
 * 사용자 상세 조회
 */
async function getUserById(id) {
    try {
        const response = await fetch(`${API_BASE_URL}/users/${id}`);

        if (!response.ok) {
            throw new Error(`HTTP error! status: ${response.status}`);
        }

        const data = await response.json();
        return data;
    } catch (error) {
        console.error(`Error fetching user ${id}:`, error);
        throw error;
    }
}

// ========================================
// Health Check
// ========================================

/**
 * API 서버 상태 확인
 */
async function checkHealth() {
    try {
        const response = await fetch(`${API_BASE_URL}/health`);
        return response.ok;
    } catch (error) {
        console.error('Health check failed:', error);
        return false;
    }
}

// ========================================
// Utility Functions
// ========================================

/**
 * 숫자를 통화로 포맷팅
 */
function formatCurrency(amount) {
    return new Intl.NumberFormat('ko-KR', {
        style: 'currency',
        currency: 'KRW',
        minimumFractionDigits: 0,
    }).format(amount);
}

/**
 * 날짜를 포맷팅
 */
function formatDate(dateString) {
    const options = {
        year: 'numeric',
        month: '2-digit',
        day: '2-digit',
        hour: '2-digit',
        minute: '2-digit',
        second: '2-digit',
    };
    return new Date(dateString).toLocaleDateString('ko-KR', options);
}

/**
 * 상태를 한글로 변환
 */
function getStatusLabel(status) {
    const statusMap = {
        PENDING: '대기중',
        PROCESSING: '처리중',
        COMPLETED: '완료',
        CANCELLED: '취소됨',
    };
    return statusMap[status] || status;
}

/**
 * 상태 배지 CSS 클래스 가져오기
 */
function getStatusBadgeClass(status) {
    return `status-${status.toLowerCase()}`;
}

/**
 * 에러 메시지 표시
 */
function showError(message) {
    alert(`❌ 오류: ${message}`);
}

/**
 * 성공 메시지 표시
 */
function showSuccess(message) {
    alert(`✅ ${message}`);
}
