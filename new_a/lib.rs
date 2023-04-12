#![cfg_attr(not(feature = "std"), no_std)]
#![allow(clippy::let_unit_value)]

#[ink::contract]
mod new_a {

    use ink::storage::Lazy;
    use ink::{
        env::Error as InkEnvError,
        prelude::{format, string::String},
    };
    use scale::{Decode, Encode};

    pub type Result<T> = core::result::Result<T, Error>;

    #[derive(Debug, PartialEq, Eq, Encode, Decode)]
    #[cfg_attr(feature = "std", derive(scale_info::TypeInfo))]
    pub enum Error {
        InkEnvError(String),
    }

    impl From<InkEnvError> for Error {
        fn from(why: InkEnvError) -> Self {
            Self::InkEnvError(format!("{:?}", why))
        }
    }

    #[derive(Debug, Default)]
    #[ink::storage_item]
    pub struct Data {
        value: bool,
    }

    #[ink(storage)]
    pub struct NewA {
        pub data: Lazy<Data>,
    }

    impl NewA {
        /// Creates a new contract.
        #[ink(constructor)]
        pub fn new() -> Self {
            Self { data: Lazy::new() }
        }

        #[ink(message)]
        pub fn value(&self) -> bool {
            self.data.get_or_default().value
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
        #[ink(message)]
        pub fn migrate(&mut self) -> Result<()> {
            let old_val = self.data.get().unwrap().value as u32;
            // if 0 set false
            let new_val = !matches!(old_val, 0);
            let mut data = self.data.get_or_default();
            data.value = new_val;
            self.data.set(&data);

            Ok(())
        }
    }

    impl Default for NewA {
        fn default() -> Self {
            Self::new()
        }
    }
}
