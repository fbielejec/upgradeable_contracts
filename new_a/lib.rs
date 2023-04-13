#![cfg_attr(not(feature = "std"), no_std)]
#![allow(clippy::let_unit_value)]

#[ink::contract]
mod a {

    use ink::{
        env::{get_contract_storage, set_contract_storage, Error as InkEnvError},
        prelude::{format, string::String},
        storage::{traits::ManualKey, Lazy},
    };
    use scale::{Decode, Encode};
    use scale_info::build::field_state;

    pub type Result<T> = core::result::Result<T, Error>;

    #[derive(Debug, PartialEq, Eq, Encode, Decode)]
    #[cfg_attr(feature = "std", derive(scale_info::TypeInfo))]
    pub enum Error {
        InkEnvError(String),
        FailedMigration,
    }

    impl From<InkEnvError> for Error {
        fn from(why: InkEnvError) -> Self {
            Self::InkEnvError(format!("{:?}", why))
        }
    }

    #[derive(Default, Debug)]
    #[ink::storage_item]
    pub struct OldState {
        pub field_1: u32,
        pub field_2: bool,
    }

    #[derive(Default, Debug)]
    #[ink::storage_item]
    pub struct UpdatedOldState {
        pub field_1: bool,
        pub field_2: u32,
    }

    #[derive(Default, Debug)]
    #[ink::storage_item]
    pub struct NewState {
        pub field_3: u16,
    }

    #[ink(storage)]
    pub struct A {
        new_state: Lazy<NewState, ManualKey<456>>,
        old_state: Lazy<UpdatedOldState, ManualKey<123>>,
    }

    impl A {
        /// Creates a new contract.
        #[ink(constructor)]
        pub fn new() -> Self {
            panic!("shoud never be called!")
        }

        #[ink(message)]
        pub fn get_values(&self) -> (bool, u32, u16) {
            let old_state = self.old_state.get_or_default();
            let new_state = self.new_state.get_or_default();

            (old_state.field_1, old_state.field_2, new_state.field_3)
        }

        /// Terminates the contract.
        ///
        /// can only be called by the contract owner
        #[ink(message)]
        pub fn terminate(&mut self) -> Result<()> {
            let caller = self.env().caller();
            self.env().terminate_contract(caller)
        }

        /// Performs a contract storage migration.
        ///
        /// Call it only once
        #[ink(message, selector = 0x4D475254)]
        pub fn migrate(&mut self) -> Result<()> {
            if let Some(old_state @ OldState { field_1, field_2 }) = get_contract_storage(&123)? {
                //

                //
            }

            Err(Error::FailedMigration)
        }
    }

    impl Default for A {
        fn default() -> Self {
            Self::new()
        }
    }
}
