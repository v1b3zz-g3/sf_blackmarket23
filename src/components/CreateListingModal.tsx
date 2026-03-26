import React, { useState, useEffect } from 'react';
import { fetchNui } from '../utils/fetchNui';
import { ConfigUI } from '../config';
import { ItemImg, PriceTag } from './SharedComponents';

interface PlayerItem {
    name: string;
    label: string;
    amount: number;
    image: string;
    type: string;
}

interface CreateListingModalProps {
    onClose: () => void;
    onCreated: () => void;
}

const CreateListingModal: React.FC<CreateListingModalProps> = ({ onClose, onCreated }) => {
    const [step, setStep]                 = useState<'pick' | 'details'>('pick');
    const [playerItems, setPlayerItems]   = useState<PlayerItem[]>([]);
    const [loadingItems, setLoadingItems] = useState(true);
    const [search, setSearch]             = useState('');

    const [selectedItem, setSelectedItem] = useState<PlayerItem | null>(null);
    const [quantity, setQuantity]         = useState(1);
    const [price, setPrice]               = useState(0);
    const [loading, setLoading]           = useState(false);
    const [error, setError]               = useState('');

    // Fetch player inventory on mount
    useEffect(() => {
        setLoadingItems(true);
        fetchNui<PlayerItem[]>('getPlayerItems')
            .then(items => {
                setPlayerItems(items ?? []);
                setLoadingItems(false);
            })
            .catch(() => setLoadingItems(false));
    }, []);

    function handleSelectItem(item: PlayerItem) {
        setSelectedItem(item);
        setQuantity(1);
        setPrice(0);
        setError('');
        setStep('details');
    }

    function handleSubmit() {
        if (!selectedItem) return;
        if (quantity < 1 || quantity > selectedItem.amount) {
            setError(`Quantity must be between 1 and ${selectedItem.amount}`);
            return;
        }
        if (price < 1) {
            setError('Price must be at least 1');
            return;
        }

        setLoading(true);
        setError('');
        fetchNui<{ success: boolean; notif?: string }>('createListing', {
            item: selectedItem.name,
            quantity,
            price,
        })
            .then(res => {
                if (res.success) { onCreated(); }
                else { setError(res.notif || 'Failed to create listing'); }
            })
            .catch(() => setError('Network error'))
            .finally(() => setLoading(false));
    }

    const filtered = playerItems.filter(i =>
        i.label.toLowerCase().includes(search.toLowerCase()) ||
        i.name.toLowerCase().includes(search.toLowerCase())
    );

    return (
        <div className="modal-overlay" onClick={e => e.target === e.currentTarget && onClose()}>
            <div className="modal-box modal-box-wide">

                {/* ── Header ── */}
                <div className="modal-header">
                    <div style={{ display: 'flex', alignItems: 'center', gap: '1vh' }}>
                        {step === 'details' && (
                            <button
                                className="modal-back-btn"
                                onClick={() => { setStep('pick'); setSelectedItem(null); setError(''); }}
                                title="Back to item list"
                            >
                                <i className="fa-solid fa-arrow-left" />
                            </button>
                        )}
                        <span>{step === 'pick' ? 'Select Item to List' : `List — ${selectedItem?.label}`}</span>
                    </div>
                    <button className="modal-close" onClick={onClose}><i className="fa-solid fa-x" /></button>
                </div>

                {/* ── Step 1: Item Picker ── */}
                {step === 'pick' && (
                    <>
                        <input
                            className="modal-input inv-search"
                            type="text"
                            placeholder="Search your inventory..."
                            value={search}
                            onChange={e => setSearch(e.target.value)}
                            autoFocus
                        />

                        {loadingItems ? (
                            <div className="inv-loading">
                                <i className="fa-solid fa-spinner fa-spin" /> Loading inventory...
                            </div>
                        ) : filtered.length === 0 ? (
                            <div className="inv-empty">
                                {playerItems.length === 0
                                    ? 'Your inventory is empty'
                                    : 'No items match your search'}
                            </div>
                        ) : (
                            <div className="inv-grid">
                                {filtered.map(item => (
                                    <button
                                        key={item.name}
                                        className="inv-card"
                                        onClick={() => handleSelectItem(item)}
                                    >
                                        <div className="inv-card-img-wrap">
                                            <ItemImg
                                                image={item.image}
                                                label={item.label}
                                                className="inv-card-img"
                                            />
                                        </div>
                                        <div className="inv-card-label">{item.label}</div>
                                        <div className="inv-card-amt">x{item.amount}</div>
                                    </button>
                                ))}
                            </div>
                        )}
                    </>
                )}

                {/* ── Step 2: Set Qty & Price ── */}
                {step === 'details' && selectedItem && (
                    <>
                        {/* Selected item preview */}
                        <div className="inv-selected-preview">
                            <div className="inv-preview-img-wrap">
                                <ItemImg
                                    image={selectedItem.image}
                                    label={selectedItem.label}
                                    className="inv-preview-img"
                                />
                            </div>
                            <div className="inv-preview-info">
                                <div className="inv-preview-name">{selectedItem.label}</div>
                                <div className="inv-preview-stock">You have: {selectedItem.amount}x</div>
                            </div>
                        </div>

                        <div className="modal-row">
                            <div className="modal-field half">
                                <label>
                                    Quantity{' '}
                                    <span style={{ color: 'rgba(255,255,255,.35)' }}>(max {selectedItem.amount})</span>
                                </label>
                                <input
                                    type="number"
                                    min={1}
                                    max={selectedItem.amount}
                                    value={quantity}
                                    onChange={e => setQuantity(Math.min(selectedItem.amount, Math.max(1, parseInt(e.target.value) || 1)))}
                                    className="modal-input"
                                    autoFocus
                                />
                            </div>
                            <div className="modal-field half">
                                <label>
                                    Price{' '}
                                    {ConfigUI.paymentType === 'crypto'
                                        ? <i className={String(ConfigUI.cryptoIcon ?? 'fa-solid fa-bitcoin-sign')} style={{ marginLeft: '0.3vh', opacity: 0.7 }} />
                                        : '($)'}
                                </label>
                                <input
                                    type="number"
                                    min={1}
                                    value={price}
                                    onChange={e => setPrice(parseInt(e.target.value) || 0)}
                                    className="modal-input"
                                />
                            </div>
                        </div>

                        {/* Live total preview */}
                        {price > 0 && quantity > 0 && (
                            <div className="inv-total-preview">
                                <span>Listing total</span>
                                <PriceTag amount={price * quantity} />
                            </div>
                        )}

                        {error && <div className="modal-error">{error}</div>}

                        <button
                            className={`side-button ${loading ? 'disable-button' : ''}`}
                            onClick={handleSubmit}
                            disabled={loading}
                        >
                            {loading
                                ? 'Listing...'
                                : <><i className="fa-solid fa-tag" style={{ marginRight: '0.6vh' }} />List Item</>
                            }
                        </button>
                    </>
                )}
            </div>
        </div>
    );
};

export default CreateListingModal;
