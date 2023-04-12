#![cfg_attr(not(feature = "std"), no_std)]
#![allow(clippy::let_unit_value)]

#[ink::contract]
mod a {
    use ink::env::DefaultEnvironment;
    use ink::storage::Lazy;
    use ink::{
        env::{
            call::{build_call, ExecutionInput},
            set_code_hash, Error as InkEnvError,
        },
        prelude::{format, string::String},
    };
    use scale::{Decode, Encode};

    pub type Selector = [u8; 4];
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
        value: u32,
    }

    #[ink(storage)]
    pub struct A {
        pub data: Lazy<Data>,
    }

    impl A {
        /// Creates a new contract.
        #[ink(constructor)]
        pub fn new() -> Self {
            let data = Data { value: 0 };
            let mut this = Self { data: Lazy::new() };
            this.data.set(&data);
            this
        }

        #[ink(message)]
        pub fn get_value(&self) -> u32 {
            self.data.get_or_default().value
        }

        #[ink(message)]
        pub fn set_value(&mut self, value: u32) -> Result<()> {
            let mut data = self.data.get_or_default();
            data.value = value;
            self.data.set(&data);
            Ok(())
        }

        /// Terminates the contract.
        ///
        /// can only be called by the contract owner
        #[ink(message)]
        pub fn terminate(&mut self) -> Result<()> {
            let caller = self.env().caller();
            self.env().terminate_contract(caller)
        }

        /// Upgrades contract code
        #[ink(message)]
        pub fn set_code(&mut self, code_hash: [u8; 32], callback: Option<Selector>) -> Result<()> {
            set_code_hash(&code_hash)?;

            // Optionally call a callback function in the new contract that performs the storage data migration.
            // By convention this function should be called `migrate`, it should take no arguments
            // and be call-able only by `this` contract's instance address.
            // To ensure the latter the `migrate` in the updated contract can e.g. check if it has an Admin role on self.
            //
            // `delegatecall` ensures that the target contract is called within the caller contracts context.
            if let Some(selector) = callback {
                build_call::<DefaultEnvironment>()
                    .delegate(Hash::from(code_hash))
                    .exec_input(ExecutionInput::new(ink::env::call::Selector::new(selector)))
                    .returns::<Result<()>>()
                    .invoke()?;
            }

            Ok(())
        }
    }

    impl Default for A {
        fn default() -> Self {
            Self::new()
        }
    }
}
