import React, { useState, useEffect } from 'react';
import './App.css';
import { debugData } from '../utils/debugData';
import { fetchNui } from '../utils/fetchNui';
import { useNuiEvent } from '../hooks/useNuiEvent';
import { useVisibility } from '../providers/VisibilityProvider';
import { Item, ICartItem, INotif, TabId, Listing } from '../types/interfaces';
import { ConfigUI, ConfigNotif, ContrabandItems } from '../config';
import TabSidebar from './TabSidebar';
import ShopItem from './ShopItem';
import GoodsTab from './GoodsTab';
import { Cart, Header, Notif } from './SharedComponents';

debugData([{ action: 'setVisible', data: true }]);

interface ClientData {
    marketItems: Item[];
    currencyAmt: number;
    playerOrders: number;
    playerCid: string;
}

const App: React.FC = () => {
    const { visible }   = useVisibility();
    const [notification, setNotification]     = useState<INotif | null>(null);
    const [searchTerm, setSearchTerm]         = useState('');
    const [activeTab, setActiveTab]           = useState<TabId>('imports');
    const [marketItems, setMarketItems]       = useState<Item[]>([]);
    const [playerCash, setPlayerCash]         = useState(0);
    const [playerOrders, setPlayerOrders]     = useState(0);
    const [playerCid, setPlayerCid]           = useState('');
    const [contrabandRequired, setContrabandRequired] = useState(60);
    const [contrabandDiscount, setContrabandDiscount] = useState(20);

    // Imports/Contraband cart state
    const [cartItems, setCartItems]           = useState<ICartItem[]>([]);
    const [pendingOrder, setPendingOrder]     = useState(false);
    const [epochTime, setEpochTime]           = useState(0);
    const [currentOrderType, setCurrentOrderType] = useState<'import' | 'contraband'>('import');

    // Goods state
    const [listings, setListings]             = useState<Listing[]>([]);
    const [sellerAlerts, setSellerAlerts]     = useState<{ listingId: number; coords: any; sealDeadline: number; label: string }[]>([]);
    const [buyerAlerts, setBuyerAlerts]       = useState<{ listingId: number; coords: any }[]>([]);

    // ── Pending amount: total cost of the active pending order ───────────────
    const pendingAmt = pendingOrder
        ? cartItems.reduce((sum, item) => {
              const qty = typeof item.quantity === 'number' ? item.quantity : 0;
              return sum + item.price * qty;
          }, 0)
        : 0;

    // ── Fetch config on mount ────────────────────────────────────────────────
    useEffect(() => {
        fetchNui<{ configData: any; notifData: any; contrabandItems: any[] }>('fetchConfig').then(data => {
            for (const [k, v] of Object.entries(data.configData)) (ConfigUI as any)[k] = v;
            for (const [k, v] of Object.entries(data.notifData)) (ConfigNotif as any)[k] = v;
            setContrabandRequired(data.configData.contrabandRequired ?? 60);
            setContrabandDiscount(data.configData.contrabandDiscount ?? 20);
            ContrabandItems.splice(0, ContrabandItems.length, ...data.contrabandItems);
        });
    }, []);

    // ── Load client data when tablet opens ──────────────────────────────────
    useEffect(() => {
        if (!visible) return;
        fetchNui<ClientData>('getClientData').then(data => {
            setMarketItems(data.marketItems ?? []);
            setPlayerCash(data.currencyAmt ?? 0);
            setPlayerOrders(data.playerOrders ?? 0);
            setPlayerCid(data.playerCid ?? '');
        });
        fetchNui<Listing[]>('getListings').then(data => setListings(data ?? []));
    }, [visible]);

    // ── NUI Events ───────────────────────────────────────────────────────────
    useNuiEvent<{ text: string; notifType: string }>('notification', d => {
        setNotification({
            icon: <i className={ConfigNotif[d.notifType]?.icon ?? 'fa-solid fa-circle-info'} />,
            colour: ConfigNotif[d.notifType]?.colour ?? '#888',
            text: d.text,
        });
    });

    useNuiEvent<Item[]>('updateMarketItems', items => {
        setMarketItems(items);
        if (cartItems.length > 0 && !pendingOrder) setCartItems([]);
    });

    useNuiEvent<{ items: Item[]; notif: string; isOwner: boolean }>('updateStock', data => {
        setMarketItems(data.items);
        if (!pendingOrder && !data.isOwner) {
            cartItems.forEach(cartItem => {
                if (typeof cartItem.quantity !== 'number') return;
                const si = data.items.find(s => s.item === cartItem.item);
                if (si && cartItem.quantity > si.stock) {
                    si.stock === 0 ? removeFromCart(cartItem.item) : updateCartItemQuant(cartItem.item, si.stock);
                    setNotification({
                        icon: <i className={ConfigNotif.error?.icon} />,
                        colour: ConfigNotif.error?.colour,
                        text: data.notif,
                    });
                }
            });
        }
    });

    useNuiEvent<{ marketItems: Item[]; order: { [key: string]: number }; epochTime: number }>('loadPendingOrder', data => {
        setMarketItems(data.marketItems);
        setPendingOrder(true);
        const cart = data.marketItems
            .filter(mi => data.order[mi.item])
            .map(mi => ({ ...mi, quantity: data.order[mi.item] }));
        setCartItems(cart);
        setEpochTime(data.epochTime);
    });

    useNuiEvent<void>('clearOrder', () => {
        setCartItems([]);
        setPendingOrder(false);
        setEpochTime(0);
    });

    useNuiEvent<number>('updateCash', amt => setPlayerCash(amt));

    useNuiEvent<Listing[]>('updateListings', data => setListings(data));

    useNuiEvent<{ listingId: number; coords: any; sealDeadline: number; label: string }>('goodsSellerAlert', data => {
        setSellerAlerts(prev => {
            const filtered = prev.filter(a => a.listingId !== data.listingId);
            return [...filtered, data];
        });
        if (activeTab !== 'goods') setActiveTab('goods');
    });

    useNuiEvent<{ listingId: number; coords: any }>('goodsBuyerAlert', data => {
        setBuyerAlerts(prev => {
            const filtered = prev.filter(a => a.listingId !== data.listingId);
            return [...filtered, data];
        });
        if (activeTab !== 'goods') setActiveTab('goods');
    });

    useNuiEvent<void>('goodsRefund', () => {
        setBuyerAlerts([]);
        setSellerAlerts([]);
    });

    // Remove GPS option from buyer's tablet once they collect their order
    useNuiEvent<number>('removeBuyerGPS', listingId => {
        setBuyerAlerts(prev => prev.filter(a => a.listingId !== listingId));
    });

    // ── Cart helpers ─────────────────────────────────────────────────────────
    function addToCart(item: Item, type: 'import' | 'contraband' = 'import') {
        if (currentOrderType !== type) {
            setCartItems([{ ...item, quantity: 1 }]);
            setCurrentOrderType(type);
        } else {
            setCartItems(prev => [...prev, { ...item, quantity: 1 }]);
        }
    }

    function removeFromCart(itemName: string) {
        setCartItems(prev => prev.filter(i => i.item !== itemName));
    }

    function updateCartItemQuant(itemName: string, quant: number | '') {
        setCartItems(prev => prev.map(i => i.item === itemName ? { ...i, quantity: quant } : i));
    }

    // ── Build item lists ─────────────────────────────────────────────────────
    const searchFilter = (items: Item[]) =>
        items.filter(i => i.label.toLowerCase().includes(searchTerm.toLowerCase()));

    const buildShopItems = (items: Item[], orderType: 'import' | 'contraband', discount = 0) =>
        searchFilter(items).map(item => {
            const inCart = cartItems.find(c => c.item === item.item);
            return (
                <ShopItem
                    key={item.item}
                    item={item}
                    discountPct={discount}
                    disableAdd={pendingOrder || !!inCart || item.stock === 0}
                    addToCart={i => addToCart(i, orderType)}
                />
            );
        });

    const contrabandAllItems: Item[] = [
        ...marketItems,
        ...ContrabandItems.map(i => ({ ...i, stock: Math.max(i.minStock, Math.min(i.maxStock, i.maxStock)) })),
    ];

    const myListings = listings.filter(l => l.seller_cid === playerCid && l.status === 'available');

    function refreshListings() {
        fetchNui<Listing[]>('getListings').then(data => setListings(data ?? []));
    }

    // ── Render ───────────────────────────────────────────────────────────────
    return (
        <div id="tablet" className={ConfigUI.tabletColour === 'dark' ? 'tablet-dark' : 'tablet-light'}>
            <div id="camera" className={ConfigUI.tabletColour === 'dark' ? 'camera-dark' : 'camera-light'} />
            <div id="tablet-screen">
                <Header
                    amt={playerCash}
                    pendingAmt={pendingAmt}
                    handleSearch={e => setSearchTerm(e.target.value)}
                />
                {notification && <Notif notifyData={notification} onDismiss={() => setNotification(null)} />}

                <div id="main-container">
                    <TabSidebar
                        activeTab={activeTab}
                        onTabChange={tab => { setActiveTab(tab); setSearchTerm(''); }}
                        playerOrders={playerOrders}
                        contrabandRequired={contrabandRequired}
                    />

                    <div id="tab-content">
                        {/* ── IMPORTS TAB ── */}
                        {activeTab === 'imports' && (
                            <>
                                <div id="items">{buildShopItems(marketItems, 'import')}</div>
                                <Cart
                                    pendingOrder={pendingOrder}
                                    cartItems={cartItems}
                                    marketItems={marketItems}
                                    epochTime={epochTime}
                                    orderType="import"
                                    removeFromCart={removeFromCart}
                                    updateCartItemQuant={updateCartItemQuant}
                                    setPendingOrder={setPendingOrder}
                                />
                            </>
                        )}

                        {/* ── GOODS TAB ── */}
                        {activeTab === 'goods' && (
                            <GoodsTab
                                listings={listings}
                                myListings={myListings}
                                playerCid={playerCid}
                                sellerAlerts={sellerAlerts}
                                buyerAlerts={buyerAlerts}
                                onRefresh={refreshListings}
                            />
                        )}

                        {/* ── CONTRABAND TAB ── */}
                        {activeTab === 'contraband' && playerOrders >= contrabandRequired && (
                            <>
                                <div id="items">
                                    {buildShopItems(marketItems, 'contraband', contrabandDiscount)}
                                    {searchFilter(ContrabandItems.map(i => ({ ...i, stock: i.maxStock }))).map(item => {
                                        const inCart = cartItems.find(c => c.item === item.item);
                                        return (
                                            <ShopItem
                                                key={item.item}
                                                item={item}
                                                discountPct={0}
                                                disableAdd={pendingOrder || !!inCart || item.stock === 0}
                                                addToCart={i => addToCart(i, 'contraband')}
                                            />
                                        );
                                    })}
                                </div>
                                <Cart
                                    pendingOrder={pendingOrder}
                                    cartItems={cartItems}
                                    marketItems={contrabandAllItems}
                                    epochTime={epochTime}
                                    orderType="contraband"
                                    removeFromCart={removeFromCart}
                                    updateCartItemQuant={updateCartItemQuant}
                                    setPendingOrder={setPendingOrder}
                                />
                            </>
                        )}
                    </div>
                </div>
            </div>
            <div id="home" />
        </div>
    );
};

export default App;