import { MutableRefObject, useEffect, useRef } from 'react';
import { noop } from '../utils/misc';

interface NuiMessageData<T = unknown> { action: string; data: T; }
type NuiHandlerSignature<T> = (data: T) => void;

export const useNuiEvent = <T = any>(action: string, handler: (data: T) => void) => {
    const savedHandler: MutableRefObject<NuiHandlerSignature<T>> = useRef(noop);
    useEffect(() => { savedHandler.current = handler; }, [handler]);
    useEffect(() => {
        const listener = (event: MessageEvent<NuiMessageData<T>>) => {
            if (event.data.action === action && savedHandler.current) {
                savedHandler.current(event.data.data);
            }
        };
        window.addEventListener('message', listener);
        return () => window.removeEventListener('message', listener);
    }, [action]);
};
