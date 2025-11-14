// ========================================
// Order Creation Page Logic - Material Design
// ========================================

let cart = [];
let currentCategory = 'all';
let allProducts = [];

// Initialize
document.addEventListener('DOMContentLoaded', async () => {
    M.AutoInit();

    // Load data from API
    await loadProducts();
    await loadUsers();

    renderCart();
});

/**
 * 상품 목록 로드
 */
async function loadProducts() {
    try {
        const products = await getProducts({ page: 1, limit: 100 });
        allProducts = products;
        renderProducts(products);
    } catch (error) {
        console.error('Failed to load products:', error);
        const container = document.getElementById('productsGrid');
        if (container) {
            container.innerHTML = `
                <div class="col s12">
                    <div class="card red lighten-4">
                        <div class="card-content red-text text-darken-4">
                            <i class="material-icons left">error</i>
                            상품 로드 실패. API 서버를 확인해주세요.
                        </div>
                    </div>
                </div>
            `;
        }
    }
}

/**
 * 상품 목록 렌더링
 */
function renderProducts(products) {
    const container = document.getElementById('productsGrid');
    if (!container) return;

    if (!products || products.length === 0) {
        container.innerHTML = `
            <div class="col s12">
                <div class="center-align grey-text" style="padding: 40px 0;">
                    <i class="material-icons" style="font-size: 64px; opacity: 0.3;">inventory_2</i>
                    <h5>상품이 없습니다</h5>
                </div>
            </div>
        `;
        return;
    }

    // 카테고리별 아이콘 및 색상 매핑
    const categoryIcons = {
        '전자제품': 'laptop',
        '패션': 'checkroom',
        '식품': 'restaurant'
    };

    const categoryColors = [
        'linear-gradient(135deg, var(--primary-color) 0%, #0d47a1 100%)',
        'linear-gradient(135deg, #f093fb 0%, #f5576c 100%)',
        'linear-gradient(135deg, #4facfe 0%, #00f2fe 100%)',
        'linear-gradient(135deg, #fa709a 0%, #fee140 100%)',
        'linear-gradient(135deg, #30cfd0 0%, #330867 100%)',
        'linear-gradient(135deg, #a8edea 0%, #fed6e3 100%)'
    ];

    let html = '';
    products.forEach((product, index) => {
        const icon = categoryIcons[product.category] || 'shopping_bag';
        const gradient = categoryColors[index % categoryColors.length];

        html += `
            <div class="col s12 m12 l6" data-category="${product.category}">
                <div class="card product-card" onclick="addToCart(${product.id}, '${product.name}', ${product.price})">
                    <div class="product-image" style="background: ${gradient};">
                        <i class="material-icons" style="font-size: 64px;">${icon}</i>
                    </div>
                    <div class="card-content">
                        <span class="card-title">${product.name}</span>
                        <p class="grey-text">${product.description || '상품 설명'}</p>
                        <p class="blue-text text-darken-2" style="font-size: 20px; font-weight: bold;">
                            ${formatCurrency(product.price)}
                        </p>
                        <p class="grey-text" style="font-size: 12px;">재고: ${product.stock}</p>
                    </div>
                    <div class="card-action">
                        <a class="blue-text">
                            <i class="material-icons left">add_shopping_cart</i>장바구니에 추가
                        </a>
                    </div>
                </div>
            </div>
        `;
    });

    container.innerHTML = html;
}

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
    const selectContainer = document.getElementById('userIdContainer');
    if (!selectContainer) return;

    if (!users || users.length === 0) {
        selectContainer.innerHTML = `
            <div class="input-field">
                <i class="material-icons prefix">person</i>
                <input id="userId" type="number" min="1" required>
                <label for="userId">사용자 ID</label>
            </div>
        `;
        M.updateTextFields();
        return;
    }

    let html = `
        <div class="input-field">
            <i class="material-icons prefix">person</i>
            <select id="userId" required>
                <option value="" disabled selected>사용자를 선택하세요</option>
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
    const selects = document.querySelectorAll('select');
    M.FormSelect.init(selects);
}

/**
 * 장바구니에 상품 추가
 */
function addToCart(productId, productName, price) {
    // 장바구니에 이미 있는지 확인
    const existingItem = cart.find(item => item.productId === productId);

    if (existingItem) {
        // 이미 있으면 수량 증가
        existingItem.quantity += 1;
        M.toast({
            html: `<i class="material-icons left">add</i>${productName} 수량이 증가했습니다`,
            classes: 'blue darken-2'
        });
    } else {
        // 새 상품 추가
        cart.push({
            productId,
            productName,
            price,
            quantity: 1
        });
        M.toast({
            html: `<i class="material-icons left">shopping_cart</i>${productName}이(가) 장바구니에 추가되었습니다`,
            classes: 'green darken-1'
        });
    }

    renderCart();
}

/**
 * 장바구니 렌더링
 */
function renderCart() {
    const cartItemsContainer = document.getElementById('cartItems');

    if (cart.length === 0) {
        cartItemsContainer.innerHTML = `
            <div class="center-align grey-text" style="padding: 30px 0;">
                <i class="material-icons" style="font-size: 48px;">shopping_cart</i>
                <p>장바구니가 비어있습니다</p>
            </div>
        `;
        updateCartTotals();
        return;
    }

    let html = '';
    cart.forEach((item, index) => {
        html += `
            <div class="cart-item">
                <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 8px;">
                    <strong>${item.productName}</strong>
                    <a class="btn-small red lighten-1" onclick="removeFromCart(${index})">
                        <i class="material-icons">delete</i>
                    </a>
                </div>
                <div style="color: #666; font-size: 14px; margin-bottom: 8px;">
                    ${formatCurrency(item.price)} × ${item.quantity}
                </div>
                <div style="display: flex; justify-content: space-between; align-items: center;">
                    <div class="btn-group">
                        <button class="btn-small blue lighten-1" onclick="decreaseQuantity(${index})">
                            <i class="material-icons">remove</i>
                        </button>
                        <span style="padding: 0 15px; font-weight: bold;">${item.quantity}</span>
                        <button class="btn-small blue lighten-1" onclick="increaseQuantity(${index})">
                            <i class="material-icons">add</i>
                        </button>
                    </div>
                    <strong>${formatCurrency(item.price * item.quantity)}</strong>
                </div>
            </div>
        `;
    });

    cartItemsContainer.innerHTML = html;
    updateCartTotals();
}

/**
 * 장바구니에서 상품 제거
 */
function removeFromCart(index) {
    const removedItem = cart[index];
    cart.splice(index, 1);

    M.toast({
        html: `<i class="material-icons left">delete</i>${removedItem.productName}이(가) 장바구니에서 제거되었습니다`,
        classes: 'red lighten-1'
    });

    renderCart();
}

/**
 * 수량 증가
 */
function increaseQuantity(index) {
    cart[index].quantity += 1;
    renderCart();
}

/**
 * 수량 감소
 */
function decreaseQuantity(index) {
    if (cart[index].quantity > 1) {
        cart[index].quantity -= 1;
        renderCart();
    } else {
        removeFromCart(index);
    }
}

/**
 * 장바구니 합계 업데이트
 */
function updateCartTotals() {
    const totalItems = cart.reduce((sum, item) => sum + item.quantity, 0);
    const totalAmount = cart.reduce((sum, item) => sum + (item.price * item.quantity), 0);

    document.getElementById('totalItems').textContent = totalItems;
    document.getElementById('totalAmount').textContent = formatCurrency(totalAmount);
}

/**
 * 장바구니 비우기
 */
function clearCart() {
    if (cart.length === 0) {
        M.toast({html: '장바구니가 이미 비어있습니다', classes: 'orange'});
        return;
    }

    cart = [];
    renderCart();

    M.toast({
        html: '<i class="material-icons left">delete_sweep</i>장바구니가 비워졌습니다',
        classes: 'orange darken-1'
    });
}

/**
 * 주문 검증
 */
function validateOrder() {
    const userId = document.getElementById('userId').value;

    // 사용자 ID 검증
    if (!userId) {
        M.toast({
            html: '<i class="material-icons left">error</i>사용자 ID를 입력해주세요',
            classes: 'red darken-2'
        });
        return false;
    }

    if (isNaN(userId) || parseInt(userId) <= 0) {
        M.toast({
            html: '<i class="material-icons left">error</i>유효한 사용자 ID를 입력해주세요',
            classes: 'red darken-2'
        });
        return false;
    }

    // 장바구니 검증
    if (cart.length === 0) {
        M.toast({
            html: '<i class="material-icons left">error</i>장바구니에 상품을 추가해주세요',
            classes: 'red darken-2'
        });
        return false;
    }

    return true;
}

/**
 * 주문 데이터 생성
 */
function buildOrderData() {
    const userId = parseInt(document.getElementById('userId').value);

    return {
        userId,
        items: cart.map(item => ({
            productId: item.productId,
            productName: item.productName,
            quantity: item.quantity,
            price: item.price
        }))
    };
}

/**
 * 주문 제출
 */
async function submitOrder() {
    // 검증
    if (!validateOrder()) {
        return;
    }

    try {
        const orderData = buildOrderData();

        // 로딩 토스트 표시
        M.toast({
            html: '<i class="material-icons left">hourglass_empty</i>주문 생성 중...',
            classes: 'blue darken-2',
            displayLength: 2000
        });

        const response = await createOrder(orderData);

        // 성공 토스트
        M.toast({
            html: `<i class="material-icons left">check_circle</i>주문이 성공적으로 생성되었습니다! (주문 #${response.id})`,
            classes: 'green darken-1',
            displayLength: 4000
        });

        // 폼 초기화
        setTimeout(() => {
            document.getElementById('userId').value = '';
            cart = [];
            renderCart();

            // Materialize label 업데이트
            M.updateTextFields();
        }, 1500);

    } catch (error) {
        M.toast({
            html: `<i class="material-icons left">error</i>${error.message || '주문 생성에 실패했습니다'}`,
            classes: 'red darken-2',
            displayLength: 4000
        });
    }
}

/**
 * 카테고리 필터링
 */
function filterCategory(category) {
    currentCategory = category;

    const products = document.querySelectorAll('[data-category]');

    products.forEach(product => {
        if (category === 'all' || product.getAttribute('data-category') === category) {
            product.style.display = 'block';
        } else {
            product.style.display = 'none';
        }
    });

    // 활성 칩 스타일 업데이트
    const chips = document.querySelectorAll('.category-chip');
    chips.forEach(chip => {
        chip.classList.remove('blue', 'white-text');
    });

    event.target.classList.add('blue', 'white-text');
}
