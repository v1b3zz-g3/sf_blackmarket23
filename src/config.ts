export interface IConfigUI {
    [key: string]: string | number;
}

export interface INotifStyle {
    colour: string;
    icon: string;
}

export interface IConfigNotif<T> {
    [key: string]: T;
}

export const ConfigUI: IConfigUI = {};
export const ConfigNotif: IConfigNotif<INotifStyle> = {};
export let ContrabandItems: any[] = [];
