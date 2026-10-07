# MediSmart UI

MediSmart is a Flutter application designed for managing billing in a medical store. It provides a user-friendly interface for generating bills, managing customer details, and tracking sales history.

## Features

- **Customer Management**: Easily add and manage customer details, including name, mobile number, and address.
- **Billing Process**: Generate bills with item selection, automatic total calculation, and GST inclusion.
- **Bill Preview**: View a detailed preview of the bill before finalizing it, including customer and store information.
- **Bill History**: Access and edit previous bills, allowing for easy tracking of sales and customer interactions.
- **Real-time Stock Updates**: Automatically update stock levels as items are added or removed from bills.
- **Item Search Functionality**: Quickly find items using a search feature to enhance user experience.
- **Input Validation**: Ensure accurate data entry with mobile number validation and customer name formatting.

## Project Structure

```
medismart_ui
├── lib
│   ├── main.dart
│   ├── screens
│   │   ├── billing_screen.dart
│   │   ├── bill_preview_screen.dart
│   │   └── bill_history_screen.dart
│   ├── models
│   │   ├── customer.dart
│   │   ├── item.dart
│   │   └── bill.dart
│   ├── services
│   │   ├── db_helper.dart
│   │   ├── billing_service.dart
│   │   ├── stock_service.dart
│   │   └── gst_service.dart
│   ├── widgets
│   │   ├── customer_form.dart
│   │   ├── item_search.dart
│   │   ├── bill_item_row.dart
│   │   └── bill_preview_widget.dart
│   └── utils
│       ├── formatters.dart
│       └── validators.dart
├── pubspec.yaml
├── analysis_options.yaml
├── test
│   └── billing_test.dart
└── README.md
```

## Setup Instructions

1. **Clone the Repository**: 
   ```
   git clone <repository-url>
   ```

2. **Navigate to the Project Directory**: 
   ```
   cd medismart_ui
   ```

3. **Install Dependencies**: 
   ```
   flutter pub get
   ```

4. **Run the Application**: 
   ```
   flutter run
   ```

## Contribution

Contributions are welcome! Please feel free to submit a pull request or open an issue for any enhancements or bug fixes.

## License

This project is licensed under the MIT License. See the LICENSE file for details.