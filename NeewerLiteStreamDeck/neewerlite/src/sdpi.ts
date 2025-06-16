// Ref: https://sdpi-components.dev/docs/helpers/data-source#payload-structure

export type Light = {
  id: string;
  name: string;
  brightness: number;
  temperature: number;
  supportRGB: number;
  maxChannel: number;
  cctRange: string;
  state: number; // -1 offline, 0 off, 1 on
};

export type DataSourcePayload = {
	event: string;
	items: DataSourceResult;
};

export type DataSourceResult = DataSourceResultItem[];

export type DataSourceResultItem = Item | ItemGroup;

export type Item = {
	disabled?: boolean;
	label?: string;
	value: string;
};

export type ItemGroup = {
	label?: string;
	children: Item[];
};

export type GlobalSettings = {
	lights: Light[];
	app_connected: boolean;
};

export type FXItem = {
	label: string;
	value: string;
};

export function getFX17Items(): FXItem[] {
	return [
		{value: "1", label: "Lighting"},
		{value: "2", label: "Paparazzi"},
		{value: "3", label: "Defective bulb"},
		{value: "4", label: "Explosion"},
		{value: "5", label: "Welding"},
		{value: "6", label: "CCT flash"},
		{value: "7", label: "HUE flash"},
		{value: "8", label: "CCT pulse"},
		{value: "9", label: "HUE pulse"},
		{value: "10", label: "Cop car"},
		{value: "11", label: "Candle light"},
		{value: "12", label: "HUE loop"},
		{value: "13", label: "CCT loop"},
		{value: "14", label: "INT loop"},
		{value: "15", label: "TV screen"},
		{value: "16", label: "Firework"},
		{value: "17", label: "Party"}
	];
}

export function getFX9Items(): FXItem[] {
	return [
		{value: "1", label: "Squard Car"},
		{value: "2", label: "Ambulance"},
		{value: "3", label: "Fire Engine"},
		{value: "4", label: "Fireworks"},
		{value: "5", label: "Party"},
		{value: "6", label: "Candle Light"},
		{value: "7", label: "Paparazzi"},
		{value: "8", label: "Screen"},
		{value: "9", label: "Lighting"}
	];
}