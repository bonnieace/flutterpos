import {ProductInput, SaleInput, ShiftInput} from "./report";

/**
 * A made-up business date: two shifts and three categories. The tests read
 * it, and `npm run sample-day-report` renders it as the sample document Meta
 * asks for when the template is submitted.
 */

const at = (time: string) => new Date(`2026-10-14T${time}:00+03:00`);

export const SAMPLE_BUSINESS_DATE = "2026-10-14";

export const SAMPLE_PRODUCTS: ProductInput[] = [
  {id: "tusker", name: "Tusker Lager 500ml", category: "Beer"},
  {id: "whitecap", name: "White Cap 500ml", category: "Beer"},
  {id: "guinness", name: "Guinness 500ml", category: "Beer"},
  {id: "cane", name: "Kenya Cane 250ml", category: "Spirits"},
  {id: "gilbeys", name: "Gilbey's Gin 250ml", category: "Spirits"},
  {id: "jameson", name: "Jameson 350ml", category: "Spirits"},
  {id: "coke", name: "Coca-Cola 500ml", category: "Soft drinks"},
  {id: "water", name: "Water 500ml", category: "Soft drinks"},
];

export const SAMPLE_SHIFTS: ShiftInput[] = [
  {id: "day", staffName: "John K.", status: "closed",
    startTime: at("10:00"), endTime: at("16:00")},
  {id: "night", staffName: "Mary W.", status: "closed",
    startTime: at("16:02"), endTime: at("23:48")},
];

const PRICES: Record<string, number> = {
  tusker: 250, whitecap: 250, guinness: 300, cane: 400,
  gilbeys: 650, jameson: 1800, coke: 80, water: 50,
};

function sale(
  time: string,
  shiftId: string,
  soldBy: string,
  payment: string,
  lines: Array<[string, number]>
): SaleInput {
  const items = lines.map(([id, quantity]) => ({
    productName: SAMPLE_PRODUCTS.find((product) => product.id === id)!.name,
    quantity,
    price: PRICES[id],
    itemid: id,
  }));
  return {
    shiftId,
    soldBy,
    payment,
    totalAmount: items.reduce((sum, item) => sum + item.quantity * item.price, 0),
    items,
    dateAdded: at(time),
  };
}

export const SAMPLE_SALES: SaleInput[] = [
  sale("11:20", "day", "John K.", "Cash", [["tusker", 20], ["coke", 12]]),
  sale("13:45", "day", "John K.", "Mpesa", [["guinness", 6], ["whitecap", 10], ["gilbeys", 4]]),
  sale("15:30", "day", "John K.", "Mpesa", [["cane", 8], ["jameson", 1], ["water", 11]]),
  sale("18:10", "night", "Mary W.", "Cash", [["tusker", 42], ["coke", 15], ["water", 10]]),
  sale("19:25", "night", "Mary W.", "Mpesa", [["guinness", 18], ["whitecap", 24], ["gilbeys", 9]]),
  sale("22:40", "night", "Mary W.", "Mpesa", [["cane", 12], ["jameson", 3]]),
];
