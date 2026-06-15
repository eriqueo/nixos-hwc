import { Item, ItemStore } from "./contracts.js";

export class InMemoryItemStore implements ItemStore {
  private items = new Map<string, Item>();

  async load(id: string): Promise<Item | null> {
    const it = this.items.get(id);
    return it ? structuredClone(it) : null;
  }

  async save(item: Item): Promise<void> {
    this.items.set(item.id, structuredClone(item));
  }

  async list(): Promise<Item[]> {
    return Array.from(this.items.values()).map((i) => structuredClone(i));
  }
}
