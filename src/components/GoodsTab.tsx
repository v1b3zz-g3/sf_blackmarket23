import React, { useState, useEffect } from 'react';
import { Listing } from '../types/interfaces';
import { fetchNui } from '../utils/fetchNui';
import { ItemImg, PriceTag } from './SharedComponents';
import CreateListingModal from './CreateListingModal';

interface GoodsTabProps {
    listings: Listing[];
    myListings: Listing[];
    playerCid: string;
    sellerAlerts: { listingId: number; coords: any; sealDeadline: number; label: string }[];
    buyerAlerts: { listingId: number; coords: any }[];
    onRefresh: () => void;
}

function formatTimeLeft(sealDeadline: number): string {
    const diff = sealDeadline - Math.floor(Date.now() / 1000);
    if (diff <= 0) return 'Expired';
    const m = Math.floor(diff / 60);
    const s = diff % 60;
    return `${m}:${s.toString().padStart(2, '0')}`;
}

const GoodsTab: React.FC<GoodsTabProps> = ({ listings, myListings, playerCid, sellerAlerts, buyerAlerts, onRefresh }) => {
    const [showModal, setShowModal]   = useState(false);
    const [activeView, setActiveView] = useState<'market' | 'mine'>('market');
    const [buying, setBuying]         = useState<number | null>(null);
    const [, setTick]                 = useState(0);

    // Countdown ticker
    useEffect(() => {
        const interval = setInterval(() => setTick(t => t + 1), 1000);
        return () => clearInterval(interval);
    }, []);

    function handleBuy(listingId: number) {
        setBuying(listingId);
        fetchNui<{ success: boolean; notif?: string }>('buyListing', { listingId })
            .then(res => { if (res.success) onRefresh(); })
            .finally(() => setBuying(null));
    }

    function handleRemove(listingId: number) {
        fetchNui<{ success: boolean }>('removeListing', { listingId })
            .then(res => { if (res.success) onRefresh(); });
    }

    function handleGPS(coords: any) {
        fetchNui('goodsDeliveryLocation', { coords });
    }

    const available = listings.filter(l => l.status === 'available');
    const mySales   = listings.filter(l => l.status === 'sold' && l.seller_cid === playerCid);
    const myPending = listings.filter(l => l.status === 'sold' && l.buyer_cid === playerCid);

    return (
        <div className="goods-tab">
            {/* ── Alert banners ── */}
            {sellerAlerts.map(alert => (
                <div key={alert.listingId} className="goods-alert seller-alert">
                    <i className="fa-solid fa-truck" />
                    <div className="goods-alert-text">
                        <strong>Deliver "{alert.label}"</strong>
                        <span>Seal deadline: {formatTimeLeft(alert.sealDeadline)}</span>
                    </div>
                    <button className="goods-gps-btn" onClick={() => handleGPS(alert.coords)}>
                        <i className="fa-solid fa-location-dot" /> GPS
                    </button>
                </div>
            ))}
            {buyerAlerts.map(alert => (
                <div key={alert.listingId} className="goods-alert buyer-alert">
                    <i className="fa-solid fa-box-open" />
                    <div className="goods-alert-text">
                        <strong>Your order is ready!</strong>
                        <span>Go pick up your container</span>
                    </div>
                    <button className="goods-gps-btn" onClick={() => handleGPS(alert.coords)}>
                        <i className="fa-solid fa-location-dot" /> GPS
                    </button>
                </div>
            ))}

            {/* ── View toggle ── */}
            <div className="goods-header">
                <div className="goods-tabs-toggle">
                    <button
                        className={`goods-toggle-btn ${activeView === 'market' ? 'active' : ''}`}
                        onClick={() => setActiveView('market')}
                    >Market</button>
                    <button
                        className={`goods-toggle-btn ${activeView === 'mine' ? 'active' : ''}`}
                        onClick={() => setActiveView('mine')}
                    >My Listings</button>
                </div>
                <button className="side-button goods-list-btn" onClick={() => setShowModal(true)}>
                    <i className="fa-solid fa-plus" /> List Item
                </button>
            </div>

            {/* ── Market view ── */}
            {activeView === 'market' && (
                <div className="goods-list">
                    {available.length === 0 && (
                        <div id="checkout-empty">No items listed yet</div>
                    )}
                    {available.map(listing => {
                        const isOwn = listing.seller_cid === playerCid;
                        const isBuying = buying === listing.id;
                        return (
                            <div key={listing.id} className="goods-card">
                                <ItemImg image={listing.image} label={listing.label} className="goods-img" />
                                <div className="goods-info">
                                    <div className="goods-name">{listing.label}</div>
                                    {/* Always show Anonymous — never reveal the seller */}
                                    <div className="goods-meta">
                                        <span>{listing.quantity}x</span>
                                        <span className="goods-seller">Anonymous</span>
                                    </div>
                                    <div className="goods-price-inline">
                                        <PriceTag amount={listing.price} />
                                    </div>
                                </div>
                                {/* Buy button sits on the right, vertically centered */}
                                <button
                                    className={`goods-buy-btn ${(isBuying || isOwn) ? 'disable-button' : ''}`}
                                    disabled={isBuying || isOwn}
                                    onClick={() => handleBuy(listing.id)}
                                >
                                    {isOwn ? 'Yours' : isBuying ? '...' : 'Buy'}
                                </button>
                            </div>
                        );
                    })}
                </div>
            )}

            {/* ── My Listings view ── */}
            {activeView === 'mine' && (
                <div className="goods-list">
                    {myListings.length === 0 && mySales.length === 0 && myPending.length === 0 && (
                        <div id="checkout-empty">You have no listings</div>
                    )}

                    {/* Pending sales (seller needs to deliver) */}
                    {mySales.map(listing => {
                        const alert = sellerAlerts.find(a => a.listingId === listing.id);
                        return (
                            <div key={listing.id} className="goods-card goods-card-sold">
                                <ItemImg image={listing.image} label={listing.label} className="goods-img" />
                                <div className="goods-info">
                                    <div className="goods-name">
                                        {listing.label} <span className="badge-sold">SOLD</span>
                                    </div>
                                    <div className="goods-meta">
                                        <span>{listing.quantity}x</span>
                                    </div>
                                    {listing.seal_deadline && (
                                        <div className="goods-timer">⏱ {formatTimeLeft(listing.seal_deadline)}</div>
                                    )}
                                    <div className="goods-price-inline">
                                        <PriceTag amount={listing.price} />
                                    </div>
                                </div>
                                {alert && (
                                    <button className="goods-gps-btn" onClick={() => handleGPS(alert.coords)}>
                                        <i className="fa-solid fa-location-dot" /> GPS
                                    </button>
                                )}
                            </div>
                        );
                    })}

                    {/* Active listings */}
                    {myListings.map(listing => (
                        <div key={listing.id} className="goods-card">
                            <ItemImg image={listing.image} label={listing.label} className="goods-img" />
                            <div className="goods-info">
                                <div className="goods-name">{listing.label}</div>
                                <div className="goods-meta"><span>{listing.quantity}x</span></div>
                                <div className="goods-price-inline">
                                    <PriceTag amount={listing.price} />
                                </div>
                            </div>
                            <button className="checkout-remove goods-remove-btn" onClick={() => handleRemove(listing.id)}>
                                Remove
                            </button>
                        </div>
                    ))}

                    {/* Pending purchases (buyer waiting for seller to deliver) */}
                    {myPending.map(listing => {
                        const alert = buyerAlerts.find(a => a.listingId === listing.id);
                        return (
                            <div key={listing.id} className="goods-card goods-card-pending">
                                <ItemImg image={listing.image} label={listing.label} className="goods-img" />
                                <div className="goods-info">
                                    <div className="goods-name">
                                        {listing.label} <span className="badge-pending">AWAITING</span>
                                    </div>
                                    <div className="goods-meta"><span>{listing.quantity}x</span></div>
                                    <div className="goods-price-inline">
                                        <PriceTag amount={listing.price} />
                                    </div>
                                </div>
                                {alert && (
                                    <button className="goods-gps-btn" onClick={() => handleGPS(alert.coords)}>
                                        <i className="fa-solid fa-location-dot" /> GPS
                                    </button>
                                )}
                            </div>
                        );
                    })}
                </div>
            )}

            {showModal && (
                <CreateListingModal
                    onClose={() => setShowModal(false)}
                    onCreated={() => { setShowModal(false); onRefresh(); }}
                />
            )}
        </div>
    );
};

export default GoodsTab;