import React, { useState, useEffect } from 'react';
import { ICartItem, INotif, Item } from '../types/interfaces';
import { ConfigUI, ConfigNotif } from '../config';
import { fetchNui } from '../utils/fetchNui';
import { useNuiEvent } from '../hooks/useNuiEvent';

// ─── Image with fallback ───────────────────────────────────────────────────────
interface ItemImgProps {
    image: string;
    label?: string;
    className?: string;
}
export const ItemImg: React.FC<ItemImgProps> = ({ image, label = '', className }) => {
    const [errored, setErrored] = useState(false);
    const src = `https://cfx-nui-qs-inventory/html/images/${image}`;
    if (errored) {
        return (
            <div className={`item-img-fallback ${className ?? ''}`} title={label}>
                <i className="fa-solid fa-box" />
            </div>
        );
    }
    return (
        <img
            className={className}
            src={src}
            alt={label}
            onError={() => setErrored(true)}
        />
    );
};

// ─── Price display (bitcoin icon instead of text acronym) ─────────────────────
interface PriceTagProps {
    amount: number;
    className?: string;
    iconStyle?: React.CSSProperties;
}
export const PriceTag: React.FC<PriceTagProps> = ({ amount, className, iconStyle }) => {
    if (ConfigUI.paymentType === 'crypto') {
        return (
            <span className={className} style={{ display: 'flex', alignItems: 'center', gap: '0.35vh' }}>
                <i
                    className={String(ConfigUI.cryptoIcon ?? 'fa-solid fa-bitcoin-sign')}
                    style={{ fontSize: '1.1em', opacity: 0.85, ...iconStyle }}
                />
                {amount}
            </span>
        );
    }
    return <span className={className}>${amount}</span>;
};

// ─── CartItem Component ────────────────────────────────────────────────────────
interface CartItemProps {
    itemData: ICartItem;
    shopItemStock: number;
    removeFromCart: (item: string) => void;
    updateCartItemQuant: (item: string, quant: number | '') => void;
}

export const CartItem: React.FC<CartItemProps> = ({ itemData, shopItemStock, removeFromCart, updateCartItemQuant }) => {
    const [animClass, setAnimClass] = useState('animate__fadeInLeft');
    const totalItemPrice = typeof itemData.quantity === 'number' ? itemData.price * itemData.quantity : 0;

    function handleAnimationEnd(e: React.AnimationEvent) {
        if (e.animationName === 'fadeOutLeft') removeFromCart(itemData.item);
    }

    function handleIncrease() {
        if (typeof itemData.quantity === 'number' && itemData.quantity < shopItemStock) {
            updateCartItemQuant(itemData.item, itemData.quantity + 1);
        }
    }

    function handleDecrease() {
        if (typeof itemData.quantity === 'number' && itemData.quantity > 1) {
            updateCartItemQuant(itemData.item, itemData.quantity - 1);
        }
    }

    function handleInputChange(e: React.ChangeEvent<HTMLInputElement>) {
        const v = e.target.value !== '' ? parseInt(e.target.value) : '';
        updateCartItemQuant(itemData.item, v);
    }

    function handleInputBlur(e: React.ChangeEvent<HTMLInputElement>) {
        const v = parseInt(e.target.value);
        if (e.target.value === '' || v < 1) { updateCartItemQuant(itemData.item, 1); return; }
        if (v > shopItemStock)              { updateCartItemQuant(itemData.item, shopItemStock); return; }
        updateCartItemQuant(itemData.item, v);
    }

    return (
        <div
            onAnimationEnd={handleAnimationEnd}
            className={`checkout-item-container animate__animated ${animClass} animate__faster`}
        >
            <div className="checkout-item-left">
                <div className="checkout-item">{itemData.label}</div>
                <button onClick={() => setAnimClass('animate__fadeOutLeft')} className="checkout-remove">Remove</button>
            </div>
            <div className="checkout-item-right">
                <div className="checkout-amt">
                    <div onClick={handleDecrease} className="checkout-decrease checkout-increment">-</div>
                    <input
                        onBlur={handleInputBlur}
                        onChange={handleInputChange}
                        type="number"
                        value={itemData.quantity}
                        className="checkout-input"
                    />
                    <div onClick={handleIncrease} className="checkout-increase checkout-increment">+</div>
                </div>
                <div className="checkout-price">
                    <PriceTag amount={totalItemPrice} />
                </div>
            </div>
        </div>
    );
};

// ─── OrderItem Component ───────────────────────────────────────────────────────
interface OrderItemProps { quantity: number; label: string; price: number; }
export const OrderItem: React.FC<OrderItemProps> = ({ quantity, label, price }) => (
    <div className="order-item-container">
        <div className="order-left">
            <div className="order-item-amt">{quantity}x</div>
            <div className="order-item">{label}</div>
        </div>
        <div className="order-item-price">
            <PriceTag amount={price * quantity} />
        </div>
    </div>
);

// ─── Checkout Component ────────────────────────────────────────────────────────
interface CheckoutProps {
    total: number;
    items: ICartItem[];
    pendingOrder: boolean;
    epochTime: number;
    orderType: 'import' | 'contraband';
    setPendingOrder: (state: boolean) => void;
    onOrderReady?: () => void;
}

export const Checkout: React.FC<CheckoutProps> = ({ total, items, pendingOrder, epochTime, orderType, setPendingOrder, onOrderReady }) => {
    const [formattedTime, setFormattedTime] = useState('');
    const [orderReady, setOrderReady]       = useState(false);

    function formatTime(epoch: number) {
        const dt = new Date(epoch * 1000);
        setFormattedTime(dt.toLocaleTimeString('en-US', { hour: 'numeric', minute: 'numeric', hour12: true }));
    }

    useEffect(() => {
        epochTime > 0 ? formatTime(epochTime) : setFormattedTime('');
    }, [epochTime]);

    useNuiEvent('orderReady', () => { setOrderReady(true); onOrderReady?.(); });

    function handleCheckout() {
        fetchNui<{ success: boolean; epochTime?: number }>('submitOrder', { items, orderType })
            .then(data => {
                if (data.success) {
                    setPendingOrder(true);
                    if (data.epochTime) formatTime(data.epochTime);
                }
            });
    }

    function handleLocation() {
        if (orderReady) fetchNui('deliveryLocation');
    }

    return (
        <div id="checkout-bottom">
            <div id="checkout-delivery-time">
                <div id="checkout-total-text">{pendingOrder && formattedTime ? 'Delivery Time' : 'Est. Delivery'}</div>
                <div id="checkout-total-amt">{pendingOrder && formattedTime ? formattedTime : `${ConfigUI.estDeliveryTime} Mins`}</div>
            </div>
            <div id="checkout-total">
                <div id="checkout-total-text">Total</div>
                <div id="checkout-total-amt">
                    <PriceTag amount={total} />
                </div>
            </div>
            {pendingOrder
                ? <div onClick={handleLocation} className={`side-button ${orderReady ? '' : 'disable-button'}`}>Locate Drop Off</div>
                : <div onClick={handleCheckout} className="side-button">Checkout</div>
            }
        </div>
    );
};

// ─── Cart Component ────────────────────────────────────────────────────────────
interface CartProps {
    pendingOrder: boolean;
    marketItems: Item[];
    cartItems: ICartItem[];
    epochTime: number;
    orderType: 'import' | 'contraband';
    removeFromCart: (item: string) => void;
    updateCartItemQuant: (item: string, quant: number | '') => void;
    setPendingOrder: (state: boolean) => void;
}

export const Cart: React.FC<CartProps> = ({ cartItems, marketItems, pendingOrder, epochTime, orderType, removeFromCart, updateCartItemQuant, setPendingOrder }) => {
    const totalPrice = cartItems.reduce((total, item) => {
        const qty = typeof item.quantity === 'number' ? item.quantity : 0;
        return total + item.price * qty;
    }, 0);

    const cartItemsEl = cartItems.map(item => {
        const shopItem  = marketItems.find(s => s.item === item.item);
        const shopStock = shopItem ? shopItem.stock : 0;
        return pendingOrder
            ? <OrderItem key={item.item} quantity={typeof item.quantity === 'number' ? item.quantity : 1} label={item.label} price={item.price} />
            : <CartItem key={item.item} itemData={item} shopItemStock={shopStock} removeFromCart={removeFromCart} updateCartItemQuant={updateCartItemQuant} />;
    });

    return (
        <div id="checkout">
            <div className="checkout-header">{pendingOrder ? 'Pending Order' : 'Shopping Cart'}</div>
            <div id="checkout-items">
                {cartItems.length === 0
                    ? <div id="checkout-empty">Your cart is empty</div>
                    : cartItemsEl}
            </div>
            {cartItems.length > 0 && (
                <Checkout
                    total={totalPrice}
                    items={cartItems}
                    pendingOrder={pendingOrder}
                    epochTime={epochTime}
                    orderType={orderType}
                    setPendingOrder={setPendingOrder}
                />
            )}
        </div>
    );
};

// ─── Header Component ──────────────────────────────────────────────────────────
interface HeaderProps {
    amt: number;
    pendingAmt?: number;
    handleSearch: (e: React.ChangeEvent<HTMLInputElement>) => void;
}
export const Header: React.FC<HeaderProps> = ({ amt, pendingAmt, handleSearch }) => (
    <div id="top">
        <input onChange={handleSearch} id="search" type="text" placeholder="Search items..." />
        <div id="crypto" className="top-item crypto-balance-wrap">
            <i
                className={String(ConfigUI.cryptoIcon ?? 'fa-solid fa-bitcoin-sign')}
                style={{ fontSize: '1.6vh', marginRight: '0.4vh', opacity: 0.9 }}
            />
            <div className="currency-amt">{amt}</div>
            {!!pendingAmt && pendingAmt > 0 && (
                <div className="pending-badge" title="Funds locked in pending order">
                    <i className="fa-solid fa-clock" style={{ fontSize: '0.9vh', marginRight: '0.25vh' }} />
                    {pendingAmt}
                </div>
            )}
        </div>
        <div onClick={() => fetchNui('close')} id="close" className="top-item">
            <i className="fa-solid fa-x" />
        </div>
    </div>
);

// ─── Notif Component ───────────────────────────────────────────────────────────
interface NotifProps { notifyData: INotif; onDismiss: () => void; }
export const Notif: React.FC<NotifProps> = ({ notifyData, onDismiss }) => {
    const [animClass, setAnimClass] = useState('animate__backInRight');

    useEffect(() => {
        const id = setTimeout(() => setAnimClass('animate__backOutRight'), 5000);
        return () => clearTimeout(id);
    }, [notifyData]);

    function handleAnimEnd(e: React.AnimationEvent) {
        if (e.animationName === 'backOutRight') onDismiss();
    }

    return (
        <div
            id="notif"
            className={`animate__animated ${animClass}`}
            onAnimationEnd={handleAnimEnd}
            style={{ borderColor: notifyData.colour }}
        >
            <div id="notif-icon" style={{ color: notifyData.colour }}>{notifyData.icon}</div>
            <div id="notif-text">{notifyData.text}</div>
        </div>
    );
};
