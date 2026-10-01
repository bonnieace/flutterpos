/**
 * `cu_` and forty hex digits: the only customer IDs a device mints, and the
 * only ones the server acts on. A sale naming anything else is a walk-in.
 *
 * In a module of its own so the customer-sale task and the WhatsApp deliveries
 * can both read it without importing each other.
 */
export const CUSTOMER_ID_SHAPE = /^cu_[0-9a-f]{40}$/;
