import React, { Context, createContext, useContext, useEffect, useState } from 'react';
import { useNuiEvent } from '../hooks/useNuiEvent';
import { fetchNui } from '../utils/fetchNui';
import { isEnvBrowser } from '../utils/misc';

const VisibilityCtx = createContext<{ setVisible: (v: boolean) => void; visible: boolean } | null>(null);

export const VisibilityProvider: React.FC<{ children: React.ReactNode }> = ({ children }) => {
    const [visible, setVisible] = useState(false);
    useNuiEvent<boolean>('setVisible', setVisible);

    useEffect(() => {
        if (!visible) return;
        const keyHandler = (e: KeyboardEvent) => {
            if (e.code === 'Escape') {
                if (!isEnvBrowser()) fetchNui('close');
                else setVisible(v => !v);
            }
        };
        window.addEventListener('keydown', keyHandler);
        return () => window.removeEventListener('keydown', keyHandler);
    }, [visible]);

    return (
        <VisibilityCtx.Provider value={{ visible, setVisible }}>
            <div style={{ visibility: visible ? 'visible' : 'hidden', height: '100%' }}>
                {children}
            </div>
        </VisibilityCtx.Provider>
    );
};

export const useVisibility = () =>
    useContext<{ setVisible: (v: boolean) => void; visible: boolean }>(
        VisibilityCtx as Context<{ setVisible: (v: boolean) => void; visible: boolean }>
    );
