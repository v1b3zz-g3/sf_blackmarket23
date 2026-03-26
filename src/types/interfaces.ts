export interface Item {
    item: string;
    price: number;
    label: string;
    stock: number;
    image: string;
}

export interface ICartItem extends Item {
    quantity: number | "";
}

export interface INotif {
    text: string;
    colour: string;
    icon: React.ReactNode;
}

export interface Listing {
    id: number;
    seller_cid: string;
    seller_name: string;
    item: string;
    label: string;
    quantity: number;
    price: number;
    image: string;
    status: string;
    buyer_cid: string | null;
    buyer_name: string | null;
    location_index: number | null;
    sealed: number;
    seal_deadline: number | null;
    created_at: string;
}

export type TabId = 'imports' | 'goods' | 'contraband';
