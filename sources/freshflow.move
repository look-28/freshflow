module freshflow::marketplace {

    use sui::balance::{Self, Balance};
    use sui::event::{Self};
    use sui::sui::SUI;

    /// Error codes
    const EItemNotAvailable: u64 = 0;
    const EInsufficientBalance: u64 = 1;
    const EInvalidItemID: u64 = 2;

    /// Events
    public struct ItemListed has copy, drop {
        item_id: ID,
        name: vector<u8>,
        price: u64,
        expiration_date: u64,
    }

    public struct ItemPurchased has copy, drop {
        item_id: ID,
        buyer: address,
        amount: u64,
    }

    /// Inventory item structure
    public struct Item has key {
        id: UID,
        name: vector<u8>,         // Name of the item
        provider: address,        // Seller's address
        base_price: u64,          // Base price of the item
        expiration_date: u64,     // Expiration timestamp
        active: bool,             // Is the item still available?
        balance: Balance<SUI>,    // Accumulated payment for the item
    }

    /// Provider capabilities
    public struct ProviderCap has key, store {
        id: UID,
        item_id: ID,
    }

    /// Helper function to calculate dynamic price based on expiration
    public fun calculate_price(item: &Item, current_time: u64): u64 {
        let time_to_expiry = item.expiration_date - current_time;
        if (time_to_expiry <= 86400 /* 1 day in seconds */) {
            item.base_price / 2 // 50% discount if close to expiration
        } else {
            item.base_price
        }
    }

    /// Function to list an item in the marketplace
    public fun list_item(
        name: vector<u8>,
        base_price: u64,
        expiration_date: u64,
        ctx: &mut TxContext,
    ): ProviderCap {
        let item = Item {
            id: object::new(ctx),
            name,
            provider: tx_context::sender(ctx),
            base_price,
            expiration_date,
            active: true,
            balance: balance::zero(),
        };

        let provider_cap = ProviderCap {
            id: object::new(ctx),
            item_id: object::uid_to_inner(&item.id),
        };

        event::emit(ItemListed {
            item_id: object::uid_to_inner(&item.id),
            name: item.name,
            price: item.base_price,
            expiration_date: item.expiration_date,
        });

        transfer::share_object(item);
        provider_cap
    }

    /// Function to purchase an item
    public fun purchase_item(
        item: &mut Item,
        mut buyer_balance: Balance<SUI>,
        current_time: u64,
        ctx: &mut TxContext,
    ): Balance<SUI> {
        assert!(item.active, EItemNotAvailable);
        let price = calculate_price(item, current_time);
        assert!(buyer_balance.value() >= price, EInsufficientBalance);

        let payment = balance::split(&mut buyer_balance, price);
        balance::join(&mut item.balance, payment);

        event::emit(ItemPurchased {
            item_id: object::uid_to_inner(&item.id),
            buyer: ctx.sender(),
            amount: price,
        });

        buyer_balance
    }

    /// Function for providers to claim earnings
    public fun claim_earnings(
        item: Item,
        provider_cap: ProviderCap,
    ): Balance<SUI> {
        assert!(object::uid_to_inner(&item.id) == provider_cap.item_id, EInvalidItemID);

        let Item { id, name: _, provider: _, base_price: _, expiration_date: _, active: _, balance } = item;

        object::delete(id);

        let ProviderCap { id, item_id: _ } = provider_cap;
        object::delete(id);

        balance
    }
}
