use std::{
    collections::HashMap,
    sync::{Arc, RwLock},
};

use serde::{Deserialize, Serialize};
use uuid::Uuid;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Item {
    pub id: Uuid,
    pub name: String,
    pub done: bool,
}

#[derive(Debug, Deserialize)]
pub struct NewItem {
    pub name: String,
}

/// In-memory store. Swap this for a real database behind the same methods -
/// the handlers only talk to AppState, never to the storage directly.
#[derive(Clone, Default)]
pub struct AppState {
    items: Arc<RwLock<HashMap<Uuid, Item>>>,
}

impl AppState {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn list(&self) -> Vec<Item> {
        let items = self.items.read().expect("state lock poisoned");
        let mut out: Vec<Item> = items.values().cloned().collect();
        // HashMap iteration order is arbitrary; sort so responses are stable.
        out.sort_by(|a, b| a.name.cmp(&b.name));
        out
    }

    pub fn get(&self, id: Uuid) -> Option<Item> {
        self.items.read().expect("state lock poisoned").get(&id).cloned()
    }

    pub fn create(&self, name: String) -> Item {
        let item = Item { id: Uuid::new_v4(), name, done: false };
        self.items
            .write()
            .expect("state lock poisoned")
            .insert(item.id, item.clone());
        item
    }

    pub fn set_done(&self, id: Uuid, done: bool) -> Option<Item> {
        let mut items = self.items.write().expect("state lock poisoned");
        let item = items.get_mut(&id)?;
        item.done = done;
        Some(item.clone())
    }

    pub fn delete(&self, id: Uuid) -> bool {
        self.items.write().expect("state lock poisoned").remove(&id).is_some()
    }
}
