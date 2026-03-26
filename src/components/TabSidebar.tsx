import React from 'react';
import { TabId } from '../types/interfaces';

interface TabSidebarProps {
    activeTab: TabId;
    onTabChange: (tab: TabId) => void;
    playerOrders: number;
    contrabandRequired: number;
}

const tabs: { id: TabId; icon: string; label: string }[] = [
    { id: 'imports',    icon: 'fa-solid fa-ship',             label: 'Imports'    },
    { id: 'goods',      icon: 'fa-solid fa-handshake',        label: 'Goods'      },
    { id: 'contraband', icon: 'fa-solid fa-skull-crossbones', label: 'Contraband' },
];

const TabSidebar: React.FC<TabSidebarProps> = ({ activeTab, onTabChange, playerOrders, contrabandRequired }) => {
    const isContrabandLocked = playerOrders < contrabandRequired;

    return (
        <div className="tab-sidebar">
            {tabs.map(tab => {
                const locked = tab.id === 'contraband' && isContrabandLocked;
                const active = activeTab === tab.id;
                return (
                    <div
                        key={tab.id}
                        className={`tab-item ${active ? 'tab-active' : ''} ${locked ? 'tab-locked' : ''}`}
                        onClick={() => !locked && onTabChange(tab.id)}
                        title={locked ? `Requires ${contrabandRequired} orders (you have ${playerOrders})` : tab.label}
                    >
                        <div className="tab-icon">
                            <i className={locked ? 'fa-solid fa-lock' : tab.icon}></i>
                        </div>
                        <div className="tab-label">
                            {tab.label}
                            {locked && (
                                <span className="tab-lock-info">{playerOrders}/{contrabandRequired}</span>
                            )}
                        </div>
                        {active && <div className="tab-active-bar" />}
                    </div>
                );
            })}
        </div>
    );
};

export default TabSidebar;
