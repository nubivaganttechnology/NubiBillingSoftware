import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_bn.dart';
import 'app_localizations_en.dart';
import 'app_localizations_hi.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('bn'),
    Locale('en'),
    Locale('hi'),
  ];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'NubiBill ERP'**
  String get appTitle;

  /// No description provided for @workspace.
  ///
  /// In en, this message translates to:
  /// **'WORKSPACE'**
  String get workspace;

  /// No description provided for @dashboard.
  ///
  /// In en, this message translates to:
  /// **'Dashboard'**
  String get dashboard;

  /// No description provided for @billing.
  ///
  /// In en, this message translates to:
  /// **'POS Billing'**
  String get billing;

  /// No description provided for @sales.
  ///
  /// In en, this message translates to:
  /// **'Sales'**
  String get sales;

  /// No description provided for @purchases.
  ///
  /// In en, this message translates to:
  /// **'Purchases'**
  String get purchases;

  /// No description provided for @products.
  ///
  /// In en, this message translates to:
  /// **'Products'**
  String get products;

  /// No description provided for @godowns.
  ///
  /// In en, this message translates to:
  /// **'Godowns'**
  String get godowns;

  /// No description provided for @racks.
  ///
  /// In en, this message translates to:
  /// **'Racks'**
  String get racks;

  /// No description provided for @barcode.
  ///
  /// In en, this message translates to:
  /// **'Barcode'**
  String get barcode;

  /// No description provided for @customers.
  ///
  /// In en, this message translates to:
  /// **'Customers'**
  String get customers;

  /// No description provided for @suppliers.
  ///
  /// In en, this message translates to:
  /// **'Suppliers'**
  String get suppliers;

  /// No description provided for @expenses.
  ///
  /// In en, this message translates to:
  /// **'Expenses'**
  String get expenses;

  /// No description provided for @staffRoles.
  ///
  /// In en, this message translates to:
  /// **'Staff & Roles'**
  String get staffRoles;

  /// No description provided for @settings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settings;

  /// No description provided for @businesses.
  ///
  /// In en, this message translates to:
  /// **'Businesses'**
  String get businesses;

  /// No description provided for @logout.
  ///
  /// In en, this message translates to:
  /// **'Log out'**
  String get logout;

  /// No description provided for @business.
  ///
  /// In en, this message translates to:
  /// **'Business'**
  String get business;

  /// No description provided for @outlet.
  ///
  /// In en, this message translates to:
  /// **'Outlet'**
  String get outlet;

  /// No description provided for @searchWorkspace.
  ///
  /// In en, this message translates to:
  /// **'Search workspace'**
  String get searchWorkspace;

  /// No description provided for @switchBusiness.
  ///
  /// In en, this message translates to:
  /// **'Switch business'**
  String get switchBusiness;

  /// No description provided for @switchOutlet.
  ///
  /// In en, this message translates to:
  /// **'Switch outlet'**
  String get switchOutlet;

  /// No description provided for @syncStatusSynced.
  ///
  /// In en, this message translates to:
  /// **'Synced'**
  String get syncStatusSynced;

  /// No description provided for @syncStatusSyncing.
  ///
  /// In en, this message translates to:
  /// **'Syncing'**
  String get syncStatusSyncing;

  /// No description provided for @syncStatusOffline.
  ///
  /// In en, this message translates to:
  /// **'Offline'**
  String get syncStatusOffline;

  /// No description provided for @syncStatusPending.
  ///
  /// In en, this message translates to:
  /// **'Pending'**
  String get syncStatusPending;

  /// No description provided for @syncStatusError.
  ///
  /// In en, this message translates to:
  /// **'Sync error'**
  String get syncStatusError;

  /// No description provided for @refresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get refresh;

  /// No description provided for @language.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get language;

  /// No description provided for @totalSales.
  ///
  /// In en, this message translates to:
  /// **'Total sales'**
  String get totalSales;

  /// No description provided for @totalPurchases.
  ///
  /// In en, this message translates to:
  /// **'Total purchases'**
  String get totalPurchases;

  /// No description provided for @borrowed.
  ///
  /// In en, this message translates to:
  /// **'Borrowed'**
  String get borrowed;

  /// No description provided for @collected.
  ///
  /// In en, this message translates to:
  /// **'Collected'**
  String get collected;

  /// No description provided for @payable.
  ///
  /// In en, this message translates to:
  /// **'Payable'**
  String get payable;

  /// No description provided for @active.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get active;

  /// No description provided for @inactive.
  ///
  /// In en, this message translates to:
  /// **'Inactive'**
  String get inactive;

  /// No description provided for @outOfStock.
  ///
  /// In en, this message translates to:
  /// **'Out of Stock'**
  String get outOfStock;

  /// No description provided for @lowStock.
  ///
  /// In en, this message translates to:
  /// **'Low Stock'**
  String get lowStock;

  /// No description provided for @records.
  ///
  /// In en, this message translates to:
  /// **'records'**
  String get records;

  /// No description provided for @allSettled.
  ///
  /// In en, this message translates to:
  /// **'All settled'**
  String get allSettled;

  /// No description provided for @withDues.
  ///
  /// In en, this message translates to:
  /// **'with dues'**
  String get withDues;

  /// No description provided for @liquidityVelocityTitle.
  ///
  /// In en, this message translates to:
  /// **'Commercial Liquidity & Cashflow Velocity'**
  String get liquidityVelocityTitle;

  /// No description provided for @net.
  ///
  /// In en, this message translates to:
  /// **'Net'**
  String get net;

  /// No description provided for @realizedCash.
  ///
  /// In en, this message translates to:
  /// **'Realized Cash'**
  String get realizedCash;

  /// No description provided for @borrowedUdhaar.
  ///
  /// In en, this message translates to:
  /// **'Borrowed (Udhaar)'**
  String get borrowedUdhaar;

  /// No description provided for @vendorPayables.
  ///
  /// In en, this message translates to:
  /// **'Vendor Payables'**
  String get vendorPayables;

  /// No description provided for @inventoryHealthTitle.
  ///
  /// In en, this message translates to:
  /// **'Inventory Health & Stock Intelligence'**
  String get inventoryHealthTitle;

  /// No description provided for @inventorySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Real-time store catalog distribution and replenishment alerts'**
  String get inventorySubtitle;

  /// No description provided for @optimalHealth.
  ///
  /// In en, this message translates to:
  /// **'Optimal Health'**
  String get optimalHealth;

  /// No description provided for @manageCatalog.
  ///
  /// In en, this message translates to:
  /// **'Manage Catalog'**
  String get manageCatalog;

  /// No description provided for @activeInStore.
  ///
  /// In en, this message translates to:
  /// **'Active in Store'**
  String get activeInStore;

  /// No description provided for @inactiveHidden.
  ///
  /// In en, this message translates to:
  /// **'Inactive / Hidden'**
  String get inactiveHidden;

  /// No description provided for @lowStockAlerts.
  ///
  /// In en, this message translates to:
  /// **'Low Stock Alerts'**
  String get lowStockAlerts;

  /// No description provided for @catalogActiveItems.
  ///
  /// In en, this message translates to:
  /// **'Catalog active items'**
  String get catalogActiveItems;

  /// No description provided for @draftOrArchived.
  ///
  /// In en, this message translates to:
  /// **'Draft or archived'**
  String get draftOrArchived;

  /// No description provided for @zeroUnitsRemaining.
  ///
  /// In en, this message translates to:
  /// **'0 units remaining'**
  String get zeroUnitsRemaining;

  /// No description provided for @belowReorderLevel.
  ///
  /// In en, this message translates to:
  /// **'Below reorder level'**
  String get belowReorderLevel;

  /// No description provided for @actionNeededReorder.
  ///
  /// In en, this message translates to:
  /// **'Action Needed: Reorder List'**
  String get actionNeededReorder;

  /// No description provided for @inwardNewPurchase.
  ///
  /// In en, this message translates to:
  /// **'Inward / New Purchase'**
  String get inwardNewPurchase;

  /// No description provided for @inward.
  ///
  /// In en, this message translates to:
  /// **'Inward'**
  String get inward;

  /// No description provided for @reorder.
  ///
  /// In en, this message translates to:
  /// **'Reorder'**
  String get reorder;

  /// No description provided for @allStockSufficient.
  ///
  /// In en, this message translates to:
  /// **'All inventory products are sufficiently stocked above reorder thresholds.'**
  String get allStockSufficient;

  /// No description provided for @posBillingTerminal.
  ///
  /// In en, this message translates to:
  /// **'POS Billing Terminal'**
  String get posBillingTerminal;

  /// No description provided for @newBill.
  ///
  /// In en, this message translates to:
  /// **'New Bill'**
  String get newBill;

  /// No description provided for @selectOutletBeforeBilling.
  ///
  /// In en, this message translates to:
  /// **'Select an outlet before billing.'**
  String get selectOutletBeforeBilling;

  /// No description provided for @gst.
  ///
  /// In en, this message translates to:
  /// **'GST'**
  String get gst;

  /// No description provided for @nonGst.
  ///
  /// In en, this message translates to:
  /// **'Non-GST'**
  String get nonGst;

  /// No description provided for @customerGstin.
  ///
  /// In en, this message translates to:
  /// **'Customer GSTIN (optional)'**
  String get customerGstin;

  /// No description provided for @customerGstinHint.
  ///
  /// In en, this message translates to:
  /// **'Enter GSTIN for this GST bill'**
  String get customerGstinHint;

  /// No description provided for @walkInCustomer.
  ///
  /// In en, this message translates to:
  /// **'Walk-in Customer'**
  String get walkInCustomer;

  /// No description provided for @selectCustomer.
  ///
  /// In en, this message translates to:
  /// **'Select Customer'**
  String get selectCustomer;

  /// No description provided for @change.
  ///
  /// In en, this message translates to:
  /// **'Change'**
  String get change;

  /// No description provided for @scanBarcodeOrSearch.
  ///
  /// In en, this message translates to:
  /// **'Scan barcode or search name/SKU'**
  String get scanBarcodeOrSearch;

  /// No description provided for @scanBarcodeLabel.
  ///
  /// In en, this message translates to:
  /// **'Scan barcode / Search product'**
  String get scanBarcodeLabel;

  /// No description provided for @qty.
  ///
  /// In en, this message translates to:
  /// **'Qty'**
  String get qty;

  /// No description provided for @discount.
  ///
  /// In en, this message translates to:
  /// **'Discount'**
  String get discount;

  /// No description provided for @addToCart.
  ///
  /// In en, this message translates to:
  /// **'Add to Cart'**
  String get addToCart;

  /// No description provided for @addAnotherProduct.
  ///
  /// In en, this message translates to:
  /// **'Add another product'**
  String get addAnotherProduct;

  /// No description provided for @clearCart.
  ///
  /// In en, this message translates to:
  /// **'Clear Cart'**
  String get clearCart;

  /// No description provided for @cartEmpty.
  ///
  /// In en, this message translates to:
  /// **'No items in this bill.'**
  String get cartEmpty;

  /// No description provided for @cartEmptySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Scan a barcode or search products above to start billing.'**
  String get cartEmptySubtitle;

  /// No description provided for @sku.
  ///
  /// In en, this message translates to:
  /// **'SKU'**
  String get sku;

  /// No description provided for @name.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get name;

  /// No description provided for @price.
  ///
  /// In en, this message translates to:
  /// **'Price'**
  String get price;

  /// No description provided for @taxable.
  ///
  /// In en, this message translates to:
  /// **'Taxable'**
  String get taxable;

  /// No description provided for @total.
  ///
  /// In en, this message translates to:
  /// **'Total'**
  String get total;

  /// No description provided for @action.
  ///
  /// In en, this message translates to:
  /// **'Action'**
  String get action;

  /// No description provided for @subtotal.
  ///
  /// In en, this message translates to:
  /// **'Subtotal'**
  String get subtotal;

  /// No description provided for @cgstSgst.
  ///
  /// In en, this message translates to:
  /// **'CGST + SGST'**
  String get cgstSgst;

  /// No description provided for @gstTurnedOff.
  ///
  /// In en, this message translates to:
  /// **'GST (Turned off)'**
  String get gstTurnedOff;

  /// No description provided for @roundOff.
  ///
  /// In en, this message translates to:
  /// **'Round off'**
  String get roundOff;

  /// No description provided for @grandTotal.
  ///
  /// In en, this message translates to:
  /// **'Grand Total'**
  String get grandTotal;

  /// No description provided for @billGstRate.
  ///
  /// In en, this message translates to:
  /// **'Bill GST Rate (Apply to all):'**
  String get billGstRate;

  /// No description provided for @customPercent.
  ///
  /// In en, this message translates to:
  /// **'Custom %'**
  String get customPercent;

  /// No description provided for @paymentOption.
  ///
  /// In en, this message translates to:
  /// **'PAYMENT OPTION'**
  String get paymentOption;

  /// No description provided for @paymentModeFullCash.
  ///
  /// In en, this message translates to:
  /// **'Full Cash'**
  String get paymentModeFullCash;

  /// No description provided for @paymentModeFullUpi.
  ///
  /// In en, this message translates to:
  /// **'Full UPI'**
  String get paymentModeFullUpi;

  /// No description provided for @paymentModeSplit.
  ///
  /// In en, this message translates to:
  /// **'Partial Cash & UPI'**
  String get paymentModeSplit;

  /// No description provided for @paymentModeUdhaar.
  ///
  /// In en, this message translates to:
  /// **'Borrow (Credit / Udhaar)'**
  String get paymentModeUdhaar;

  /// No description provided for @collectFullCash.
  ///
  /// In en, this message translates to:
  /// **'Collect Full Cash'**
  String get collectFullCash;

  /// No description provided for @cashReceived.
  ///
  /// In en, this message translates to:
  /// **'Cash received from customer (₹)'**
  String get cashReceived;

  /// No description provided for @changeToReturn.
  ///
  /// In en, this message translates to:
  /// **'Change to return'**
  String get changeToReturn;

  /// No description provided for @shortBy.
  ///
  /// In en, this message translates to:
  /// **'Short by'**
  String get shortBy;

  /// No description provided for @collectFullUpi.
  ///
  /// In en, this message translates to:
  /// **'Collect Full Amount via UPI'**
  String get collectFullUpi;

  /// No description provided for @showDynamicUpiQr.
  ///
  /// In en, this message translates to:
  /// **'Show Dynamic UPI QR'**
  String get showDynamicUpiQr;

  /// No description provided for @cashAmount.
  ///
  /// In en, this message translates to:
  /// **'Cash Amount (₹)'**
  String get cashAmount;

  /// No description provided for @upiAmount.
  ///
  /// In en, this message translates to:
  /// **'UPI Amount (₹)'**
  String get upiAmount;

  /// No description provided for @setRemainderToCash.
  ///
  /// In en, this message translates to:
  /// **'Set remainder to Cash'**
  String get setRemainderToCash;

  /// No description provided for @setRemainderToUpi.
  ///
  /// In en, this message translates to:
  /// **'Set remainder to UPI'**
  String get setRemainderToUpi;

  /// No description provided for @showUpiQrFor.
  ///
  /// In en, this message translates to:
  /// **'Show UPI QR for'**
  String get showUpiQrFor;

  /// No description provided for @fullAmountAllocated.
  ///
  /// In en, this message translates to:
  /// **'Full amount allocated (Cash + UPI)'**
  String get fullAmountAllocated;

  /// No description provided for @remainingToAllocate.
  ///
  /// In en, this message translates to:
  /// **'Remaining to allocate'**
  String get remainingToAllocate;

  /// No description provided for @borrowRequiresCustomer.
  ///
  /// In en, this message translates to:
  /// **'Borrow requires customer selection'**
  String get borrowRequiresCustomer;

  /// No description provided for @selectAddCustomer.
  ///
  /// In en, this message translates to:
  /// **'Select / Add Customer'**
  String get selectAddCustomer;

  /// No description provided for @cashDownPayment.
  ///
  /// In en, this message translates to:
  /// **'Cash Down Payment (Optional)'**
  String get cashDownPayment;

  /// No description provided for @upiDownPayment.
  ///
  /// In en, this message translates to:
  /// **'UPI Down Payment (Optional)'**
  String get upiDownPayment;

  /// No description provided for @setRepaymentDueDate.
  ///
  /// In en, this message translates to:
  /// **'Set Repayment Due Date (Optional)'**
  String get setRepaymentDueDate;

  /// No description provided for @dueDate.
  ///
  /// In en, this message translates to:
  /// **'Due Date'**
  String get dueDate;

  /// No description provided for @amountBorrowedDue.
  ///
  /// In en, this message translates to:
  /// **'Amount Borrowed (Due)'**
  String get amountBorrowedDue;

  /// No description provided for @finalizeAndSaveBill.
  ///
  /// In en, this message translates to:
  /// **'FINALIZE & SAVE BILL'**
  String get finalizeAndSaveBill;

  /// No description provided for @saving.
  ///
  /// In en, this message translates to:
  /// **'Saving...'**
  String get saving;

  /// No description provided for @billSaved.
  ///
  /// In en, this message translates to:
  /// **'Bill saved'**
  String get billSaved;

  /// No description provided for @printBill.
  ///
  /// In en, this message translates to:
  /// **'Print Bill'**
  String get printBill;

  /// No description provided for @sharePdf.
  ///
  /// In en, this message translates to:
  /// **'Share PDF'**
  String get sharePdf;

  /// No description provided for @done.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get done;

  /// No description provided for @productDetails.
  ///
  /// In en, this message translates to:
  /// **'Product Details & Pricing'**
  String get productDetails;

  /// No description provided for @sellingPrice.
  ///
  /// In en, this message translates to:
  /// **'Selling price (₹)'**
  String get sellingPrice;

  /// No description provided for @mrp.
  ///
  /// In en, this message translates to:
  /// **'MRP (₹)'**
  String get mrp;

  /// No description provided for @availableStock.
  ///
  /// In en, this message translates to:
  /// **'Available stock'**
  String get availableStock;

  /// No description provided for @makeDefaultPrice.
  ///
  /// In en, this message translates to:
  /// **'Make default for this product'**
  String get makeDefaultPrice;

  /// No description provided for @savePrices.
  ///
  /// In en, this message translates to:
  /// **'Save prices'**
  String get savePrices;

  /// No description provided for @cartItems.
  ///
  /// In en, this message translates to:
  /// **'Cart Items'**
  String get cartItems;

  /// No description provided for @billSummary.
  ///
  /// In en, this message translates to:
  /// **'Bill Summary'**
  String get billSummary;

  /// No description provided for @due.
  ///
  /// In en, this message translates to:
  /// **'Due'**
  String get due;

  /// No description provided for @advance.
  ///
  /// In en, this message translates to:
  /// **'Advance'**
  String get advance;

  /// No description provided for @limit.
  ///
  /// In en, this message translates to:
  /// **'Limit'**
  String get limit;

  /// No description provided for @inStock.
  ///
  /// In en, this message translates to:
  /// **'In Stock'**
  String get inStock;

  /// No description provided for @unit.
  ///
  /// In en, this message translates to:
  /// **'Unit'**
  String get unit;

  /// No description provided for @hsn.
  ///
  /// In en, this message translates to:
  /// **'HSN'**
  String get hsn;

  /// No description provided for @salesManagement.
  ///
  /// In en, this message translates to:
  /// **'Sales Management & Invoicing'**
  String get salesManagement;

  /// No description provided for @salesHistoryAndSearch.
  ///
  /// In en, this message translates to:
  /// **'Sales Invoices & History'**
  String get salesHistoryAndSearch;

  /// No description provided for @newSale.
  ///
  /// In en, this message translates to:
  /// **'New Sale'**
  String get newSale;

  /// No description provided for @createInvoice.
  ///
  /// In en, this message translates to:
  /// **'Create New Invoice'**
  String get createInvoice;

  /// No description provided for @salesInvoices.
  ///
  /// In en, this message translates to:
  /// **'Sales Invoices'**
  String get salesInvoices;

  /// No description provided for @allBills.
  ///
  /// In en, this message translates to:
  /// **'All Bills'**
  String get allBills;

  /// No description provided for @paidStatus.
  ///
  /// In en, this message translates to:
  /// **'Paid'**
  String get paidStatus;

  /// No description provided for @borrowPending.
  ///
  /// In en, this message translates to:
  /// **'Borrow / Pending'**
  String get borrowPending;

  /// No description provided for @refundReturn.
  ///
  /// In en, this message translates to:
  /// **'Refund / Return'**
  String get refundReturn;

  /// No description provided for @billSearch.
  ///
  /// In en, this message translates to:
  /// **'Bill Search'**
  String get billSearch;

  /// No description provided for @billId.
  ///
  /// In en, this message translates to:
  /// **'Bill ID'**
  String get billId;

  /// No description provided for @customerNamePrefix.
  ///
  /// In en, this message translates to:
  /// **'Customer Name'**
  String get customerNamePrefix;

  /// No description provided for @phone.
  ///
  /// In en, this message translates to:
  /// **'Phone'**
  String get phone;

  /// No description provided for @dateRange.
  ///
  /// In en, this message translates to:
  /// **'Date Range'**
  String get dateRange;

  /// No description provided for @clearFilters.
  ///
  /// In en, this message translates to:
  /// **'Clear Filters'**
  String get clearFilters;

  /// No description provided for @search.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get search;

  /// No description provided for @viewDetail.
  ///
  /// In en, this message translates to:
  /// **'View Detail'**
  String get viewDetail;

  /// No description provided for @editBill.
  ///
  /// In en, this message translates to:
  /// **'Edit Bill'**
  String get editBill;

  /// No description provided for @paySettle.
  ///
  /// In en, this message translates to:
  /// **'Pay / Settle'**
  String get paySettle;

  /// No description provided for @deleteBill.
  ///
  /// In en, this message translates to:
  /// **'Delete Bill'**
  String get deleteBill;

  /// No description provided for @upiQr.
  ///
  /// In en, this message translates to:
  /// **'UPI QR'**
  String get upiQr;

  /// No description provided for @customerAndInvoice.
  ///
  /// In en, this message translates to:
  /// **'Customer & Invoice'**
  String get customerAndInvoice;

  /// No description provided for @saleItems.
  ///
  /// In en, this message translates to:
  /// **'Sale Items'**
  String get saleItems;

  /// No description provided for @addProductVariant.
  ///
  /// In en, this message translates to:
  /// **'Add Product / Variant'**
  String get addProductVariant;

  /// No description provided for @invoiceSummary.
  ///
  /// In en, this message translates to:
  /// **'Invoice Summary'**
  String get invoiceSummary;

  /// No description provided for @postSale.
  ///
  /// In en, this message translates to:
  /// **'Post & Save Sale'**
  String get postSale;

  /// No description provided for @postingLocally.
  ///
  /// In en, this message translates to:
  /// **'Posting locally...'**
  String get postingLocally;

  /// No description provided for @totalInvoices.
  ///
  /// In en, this message translates to:
  /// **'Total Invoices'**
  String get totalInvoices;

  /// No description provided for @totalBilled.
  ///
  /// In en, this message translates to:
  /// **'Total Billed'**
  String get totalBilled;

  /// No description provided for @totalCollected.
  ///
  /// In en, this message translates to:
  /// **'Total Collected'**
  String get totalCollected;

  /// No description provided for @outstandingDue.
  ///
  /// In en, this message translates to:
  /// **'Outstanding Due'**
  String get outstandingDue;

  /// No description provided for @allocated.
  ///
  /// In en, this message translates to:
  /// **'Allocated'**
  String get allocated;

  /// No description provided for @required.
  ///
  /// In en, this message translates to:
  /// **'Required'**
  String get required;

  /// No description provided for @remaining.
  ///
  /// In en, this message translates to:
  /// **'Remaining'**
  String get remaining;

  /// No description provided for @loadVerifiedBatches.
  ///
  /// In en, this message translates to:
  /// **'Load Verified Batches'**
  String get loadVerifiedBatches;

  /// No description provided for @noBillsFound.
  ///
  /// In en, this message translates to:
  /// **'No bills found matching filters.'**
  String get noBillsFound;

  /// No description provided for @invoiceDate.
  ///
  /// In en, this message translates to:
  /// **'Invoice Date'**
  String get invoiceDate;

  /// No description provided for @totalUnpaid.
  ///
  /// In en, this message translates to:
  /// **'Total • Unpaid'**
  String get totalUnpaid;

  /// No description provided for @refreshLocalData.
  ///
  /// In en, this message translates to:
  /// **'Refresh local data'**
  String get refreshLocalData;

  /// No description provided for @removeLine.
  ///
  /// In en, this message translates to:
  /// **'Remove line'**
  String get removeLine;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @addLine.
  ///
  /// In en, this message translates to:
  /// **'Add line'**
  String get addLine;

  /// No description provided for @loadingBatches.
  ///
  /// In en, this message translates to:
  /// **'Loading local batches...'**
  String get loadingBatches;

  /// No description provided for @allocateBaseQty.
  ///
  /// In en, this message translates to:
  /// **'Allocate base qty'**
  String get allocateBaseQty;

  /// No description provided for @batchAllocations.
  ///
  /// In en, this message translates to:
  /// **'Batch Allocations'**
  String get batchAllocations;

  /// No description provided for @repaymentDate.
  ///
  /// In en, this message translates to:
  /// **'Repayment Date'**
  String get repaymentDate;

  /// No description provided for @repaymentTimeline.
  ///
  /// In en, this message translates to:
  /// **'Repayment Timeline'**
  String get repaymentTimeline;

  /// No description provided for @allPending.
  ///
  /// In en, this message translates to:
  /// **'All Pending'**
  String get allPending;

  /// No description provided for @overdue.
  ///
  /// In en, this message translates to:
  /// **'Overdue'**
  String get overdue;

  /// No description provided for @dueToday.
  ///
  /// In en, this message translates to:
  /// **'Due Today'**
  String get dueToday;

  /// No description provided for @upcomingDue.
  ///
  /// In en, this message translates to:
  /// **'Upcoming Due'**
  String get upcomingDue;

  /// No description provided for @noRepaymentDate.
  ///
  /// In en, this message translates to:
  /// **'No Due Date'**
  String get noRepaymentDate;

  /// No description provided for @setRepaymentDate.
  ///
  /// In en, this message translates to:
  /// **'Set Due Date'**
  String get setRepaymentDate;

  /// No description provided for @changeRepaymentDate.
  ///
  /// In en, this message translates to:
  /// **'Change Due Date'**
  String get changeRepaymentDate;

  /// No description provided for @nextRepaymentDate.
  ///
  /// In en, this message translates to:
  /// **'Next Repayment Due Date'**
  String get nextRepaymentDate;

  /// No description provided for @repaymentDateUpdated.
  ///
  /// In en, this message translates to:
  /// **'Repayment date updated successfully'**
  String get repaymentDateUpdated;

  /// No description provided for @daysOverdueSuffix.
  ///
  /// In en, this message translates to:
  /// **'days overdue'**
  String get daysOverdueSuffix;

  /// No description provided for @daysRemainingSuffix.
  ///
  /// In en, this message translates to:
  /// **'days left'**
  String get daysRemainingSuffix;

  /// No description provided for @newPurchase.
  ///
  /// In en, this message translates to:
  /// **'New Purchase'**
  String get newPurchase;

  /// No description provided for @editDraftPurchase.
  ///
  /// In en, this message translates to:
  /// **'Edit Draft Purchase'**
  String get editDraftPurchase;

  /// No description provided for @saveDraft.
  ///
  /// In en, this message translates to:
  /// **'Save Draft'**
  String get saveDraft;

  /// No description provided for @reviewAndPost.
  ///
  /// In en, this message translates to:
  /// **'Review & Post'**
  String get reviewAndPost;

  /// No description provided for @supplierBill.
  ///
  /// In en, this message translates to:
  /// **'Supplier Bill'**
  String get supplierBill;

  /// No description provided for @scanBill.
  ///
  /// In en, this message translates to:
  /// **'Scan Bill'**
  String get scanBill;

  /// No description provided for @uploadImage.
  ///
  /// In en, this message translates to:
  /// **'Upload Image'**
  String get uploadImage;

  /// No description provided for @uploadPdf.
  ///
  /// In en, this message translates to:
  /// **'Upload PDF'**
  String get uploadPdf;

  /// No description provided for @purchaseItems.
  ///
  /// In en, this message translates to:
  /// **'Purchase Items'**
  String get purchaseItems;

  /// No description provided for @copyRow.
  ///
  /// In en, this message translates to:
  /// **'Copy Row'**
  String get copyRow;

  /// No description provided for @pasteFromExcel.
  ///
  /// In en, this message translates to:
  /// **'Paste from Excel'**
  String get pasteFromExcel;

  /// No description provided for @addRow.
  ///
  /// In en, this message translates to:
  /// **'Add Row'**
  String get addRow;

  /// No description provided for @filterBySupplier.
  ///
  /// In en, this message translates to:
  /// **'Filter by supplier'**
  String get filterBySupplier;

  /// No description provided for @allSuppliers.
  ///
  /// In en, this message translates to:
  /// **'All Suppliers'**
  String get allSuppliers;

  /// No description provided for @purchaseDateRange.
  ///
  /// In en, this message translates to:
  /// **'Purchase Date Range'**
  String get purchaseDateRange;

  /// No description provided for @searchPurchases.
  ///
  /// In en, this message translates to:
  /// **'Search purchase #, supplier invoice, product...'**
  String get searchPurchases;

  /// No description provided for @totalPaid.
  ///
  /// In en, this message translates to:
  /// **'Total Paid'**
  String get totalPaid;

  /// No description provided for @partiallyPaid.
  ///
  /// In en, this message translates to:
  /// **'Partially Paid'**
  String get partiallyPaid;

  /// No description provided for @supplierInvoiceNo.
  ///
  /// In en, this message translates to:
  /// **'Supplier Invoice #'**
  String get supplierInvoiceNo;

  /// No description provided for @purchaseDate.
  ///
  /// In en, this message translates to:
  /// **'Purchase Date'**
  String get purchaseDate;

  /// No description provided for @purchaseSummary.
  ///
  /// In en, this message translates to:
  /// **'Purchase Summary'**
  String get purchaseSummary;

  /// No description provided for @discountAndCharges.
  ///
  /// In en, this message translates to:
  /// **'Discount & Charges'**
  String get discountAndCharges;

  /// No description provided for @fixedAmount.
  ///
  /// In en, this message translates to:
  /// **'Fixed Amount'**
  String get fixedAmount;

  /// No description provided for @percentage.
  ///
  /// In en, this message translates to:
  /// **'Percentage'**
  String get percentage;

  /// No description provided for @recordPayment.
  ///
  /// In en, this message translates to:
  /// **'Record Payment'**
  String get recordPayment;

  /// No description provided for @approveAndReceive.
  ///
  /// In en, this message translates to:
  /// **'Approve & Receive'**
  String get approveAndReceive;

  /// No description provided for @approved.
  ///
  /// In en, this message translates to:
  /// **'Approved'**
  String get approved;

  /// No description provided for @draft.
  ///
  /// In en, this message translates to:
  /// **'Draft'**
  String get draft;

  /// No description provided for @cancelled.
  ///
  /// In en, this message translates to:
  /// **'Cancelled'**
  String get cancelled;

  /// No description provided for @noPurchasesFound.
  ///
  /// In en, this message translates to:
  /// **'No purchases found matching criteria.'**
  String get noPurchasesFound;

  /// No description provided for @productNameCol.
  ///
  /// In en, this message translates to:
  /// **'Product'**
  String get productNameCol;

  /// No description provided for @variantCol.
  ///
  /// In en, this message translates to:
  /// **'Variant / Spec'**
  String get variantCol;

  /// No description provided for @hsnCol.
  ///
  /// In en, this message translates to:
  /// **'HSN'**
  String get hsnCol;

  /// No description provided for @barcodeCol.
  ///
  /// In en, this message translates to:
  /// **'Barcode'**
  String get barcodeCol;

  /// No description provided for @batchCol.
  ///
  /// In en, this message translates to:
  /// **'Batch No'**
  String get batchCol;

  /// No description provided for @lotCol.
  ///
  /// In en, this message translates to:
  /// **'Supplier Lot'**
  String get lotCol;

  /// No description provided for @mfgDateCol.
  ///
  /// In en, this message translates to:
  /// **'Mfg Date'**
  String get mfgDateCol;

  /// No description provided for @expDateCol.
  ///
  /// In en, this message translates to:
  /// **'Expiry Date'**
  String get expDateCol;

  /// No description provided for @qtyCol.
  ///
  /// In en, this message translates to:
  /// **'Qty'**
  String get qtyCol;

  /// No description provided for @unitCol.
  ///
  /// In en, this message translates to:
  /// **'Unit'**
  String get unitCol;

  /// No description provided for @purchasePriceCol.
  ///
  /// In en, this message translates to:
  /// **'Rate (₹)'**
  String get purchasePriceCol;

  /// No description provided for @gstCol.
  ///
  /// In en, this message translates to:
  /// **'GST %'**
  String get gstCol;

  /// No description provided for @taxableCol.
  ///
  /// In en, this message translates to:
  /// **'Taxable (₹)'**
  String get taxableCol;

  /// No description provided for @mrpCol.
  ///
  /// In en, this message translates to:
  /// **'MRP (₹)'**
  String get mrpCol;

  /// No description provided for @sellingPriceCol.
  ///
  /// In en, this message translates to:
  /// **'Selling (₹)'**
  String get sellingPriceCol;

  /// No description provided for @storeLocationCol.
  ///
  /// In en, this message translates to:
  /// **'Store Location'**
  String get storeLocationCol;

  /// No description provided for @excelSpreadsheetMode.
  ///
  /// In en, this message translates to:
  /// **'Excel Grid Mode'**
  String get excelSpreadsheetMode;

  /// No description provided for @inventoryDashboardTitle.
  ///
  /// In en, this message translates to:
  /// **'Inventory Intelligence & Operations'**
  String get inventoryDashboardTitle;

  /// No description provided for @inventoryDashboardSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Real-time stock monitoring, valuations, reorder alerts & movement management'**
  String get inventoryDashboardSubtitle;

  /// No description provided for @totalItems.
  ///
  /// In en, this message translates to:
  /// **'Total Products / SKUs'**
  String get totalItems;

  /// No description provided for @inStockItems.
  ///
  /// In en, this message translates to:
  /// **'Optimal Stock'**
  String get inStockItems;

  /// No description provided for @lowStockAlertCount.
  ///
  /// In en, this message translates to:
  /// **'Low Stock Alerts'**
  String get lowStockAlertCount;

  /// No description provided for @estimatedInventoryValue.
  ///
  /// In en, this message translates to:
  /// **'Estimated Stock Value'**
  String get estimatedInventoryValue;

  /// No description provided for @reorderRequired.
  ///
  /// In en, this message translates to:
  /// **'Action Required'**
  String get reorderRequired;

  /// No description provided for @healthyCatalogRatio.
  ///
  /// In en, this message translates to:
  /// **'Healthy stock ratio'**
  String get healthyCatalogRatio;

  /// No description provided for @searchInventoryPlaceholder.
  ///
  /// In en, this message translates to:
  /// **'Search by product name, SKU, barcode...'**
  String get searchInventoryPlaceholder;

  /// No description provided for @filterAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get filterAll;

  /// No description provided for @filterInStock.
  ///
  /// In en, this message translates to:
  /// **'In Stock'**
  String get filterInStock;

  /// No description provided for @filterLowStock.
  ///
  /// In en, this message translates to:
  /// **'Low Stock'**
  String get filterLowStock;

  /// No description provided for @filterOutOfStock.
  ///
  /// In en, this message translates to:
  /// **'Out of Stock'**
  String get filterOutOfStock;

  /// No description provided for @filterInactive.
  ///
  /// In en, this message translates to:
  /// **'Inactive'**
  String get filterInactive;

  /// No description provided for @sortBy.
  ///
  /// In en, this message translates to:
  /// **'Sort by'**
  String get sortBy;

  /// No description provided for @sortNameAsc.
  ///
  /// In en, this message translates to:
  /// **'Name (A to Z)'**
  String get sortNameAsc;

  /// No description provided for @sortNameDesc.
  ///
  /// In en, this message translates to:
  /// **'Name (Z to A)'**
  String get sortNameDesc;

  /// No description provided for @sortStockAsc.
  ///
  /// In en, this message translates to:
  /// **'Stock (Low to High)'**
  String get sortStockAsc;

  /// No description provided for @sortStockDesc.
  ///
  /// In en, this message translates to:
  /// **'Stock (High to Low)'**
  String get sortStockDesc;

  /// No description provided for @sortPriceDesc.
  ///
  /// In en, this message translates to:
  /// **'Price (High to Low)'**
  String get sortPriceDesc;

  /// No description provided for @sortRecentlyUpdated.
  ///
  /// In en, this message translates to:
  /// **'Recently Updated'**
  String get sortRecentlyUpdated;

  /// No description provided for @viewModeTable.
  ///
  /// In en, this message translates to:
  /// **'Table View'**
  String get viewModeTable;

  /// No description provided for @viewModeCards.
  ///
  /// In en, this message translates to:
  /// **'Card View'**
  String get viewModeCards;

  /// No description provided for @recentlyUpdated.
  ///
  /// In en, this message translates to:
  /// **'Recently updated'**
  String get recentlyUpdated;

  /// No description provided for @last30Days.
  ///
  /// In en, this message translates to:
  /// **'Last 30 days'**
  String get last30Days;

  /// No description provided for @allTime.
  ///
  /// In en, this message translates to:
  /// **'All Time'**
  String get allTime;

  /// No description provided for @importCsv.
  ///
  /// In en, this message translates to:
  /// **'Import CSV'**
  String get importCsv;

  /// No description provided for @exportCsv.
  ///
  /// In en, this message translates to:
  /// **'Export CSV'**
  String get exportCsv;

  /// No description provided for @addNewItem.
  ///
  /// In en, this message translates to:
  /// **'Add New Product'**
  String get addNewItem;

  /// No description provided for @stockMovement.
  ///
  /// In en, this message translates to:
  /// **'Stock Action'**
  String get stockMovement;

  /// No description provided for @stockMovementReceive.
  ///
  /// In en, this message translates to:
  /// **'Receive Purchase Stock (Inward)'**
  String get stockMovementReceive;

  /// No description provided for @stockMovementAdjustIn.
  ///
  /// In en, this message translates to:
  /// **'Adjust Stock In (Found / Return)'**
  String get stockMovementAdjustIn;

  /// No description provided for @stockMovementAdjustOut.
  ///
  /// In en, this message translates to:
  /// **'Adjust Stock Out (Transfer / Sample)'**
  String get stockMovementAdjustOut;

  /// No description provided for @stockMovementDamageLoss.
  ///
  /// In en, this message translates to:
  /// **'Damage / Breakage / Expiry Loss'**
  String get stockMovementDamageLoss;

  /// No description provided for @stockMovementCountCorrection.
  ///
  /// In en, this message translates to:
  /// **'Physical Stock Count Correction'**
  String get stockMovementCountCorrection;

  /// No description provided for @currentStock.
  ///
  /// In en, this message translates to:
  /// **'Current Available Stock'**
  String get currentStock;

  /// No description provided for @quantityInBaseUnits.
  ///
  /// In en, this message translates to:
  /// **'Quantity to Adjust'**
  String get quantityInBaseUnits;

  /// No description provided for @unitCostRupees.
  ///
  /// In en, this message translates to:
  /// **'Unit Cost (₹)'**
  String get unitCostRupees;

  /// No description provided for @reasonForMovement.
  ///
  /// In en, this message translates to:
  /// **'Audit Reason / Reference'**
  String get reasonForMovement;

  /// No description provided for @reasonHint.
  ///
  /// In en, this message translates to:
  /// **'e.g., Physical count audit, vendor return, transit damage'**
  String get reasonHint;

  /// No description provided for @newStockPreview.
  ///
  /// In en, this message translates to:
  /// **'New Stock after Adjustment'**
  String get newStockPreview;

  /// No description provided for @quickAdjust.
  ///
  /// In en, this message translates to:
  /// **'Quick Adjust'**
  String get quickAdjust;

  /// No description provided for @stockHistory.
  ///
  /// In en, this message translates to:
  /// **'Stock Info & Spec'**
  String get stockHistory;

  /// No description provided for @reorderThreshold.
  ///
  /// In en, this message translates to:
  /// **'Reorder Threshold'**
  String get reorderThreshold;

  /// No description provided for @sellingPriceLabel.
  ///
  /// In en, this message translates to:
  /// **'Selling Price'**
  String get sellingPriceLabel;

  /// No description provided for @stockValuationLabel.
  ///
  /// In en, this message translates to:
  /// **'Stock Valuation'**
  String get stockValuationLabel;

  /// No description provided for @noInventoryItems.
  ///
  /// In en, this message translates to:
  /// **'No inventory items found'**
  String get noInventoryItems;

  /// No description provided for @noInventorySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Try adjusting your search keywords or filter status above'**
  String get noInventorySubtitle;

  /// No description provided for @noAccessInventory.
  ///
  /// In en, this message translates to:
  /// **'You do not have permission to access the Inventory module.'**
  String get noAccessInventory;

  /// No description provided for @stockUpdatedSuccess.
  ///
  /// In en, this message translates to:
  /// **'Stock updated successfully.'**
  String get stockUpdatedSuccess;

  /// No description provided for @inventoryExportedSuccess.
  ///
  /// In en, this message translates to:
  /// **'Inventory exported successfully.'**
  String get inventoryExportedSuccess;

  /// No description provided for @enterQuantityError.
  ///
  /// In en, this message translates to:
  /// **'Please enter a valid quantity greater than zero.'**
  String get enterQuantityError;

  /// No description provided for @stockStatusHealthy.
  ///
  /// In en, this message translates to:
  /// **'Healthy'**
  String get stockStatusHealthy;

  /// No description provided for @stockStatusLow.
  ///
  /// In en, this message translates to:
  /// **'Low Stock'**
  String get stockStatusLow;

  /// No description provided for @stockStatusOut.
  ///
  /// In en, this message translates to:
  /// **'Out of Stock'**
  String get stockStatusOut;

  /// No description provided for @stockStatusInactive.
  ///
  /// In en, this message translates to:
  /// **'Inactive'**
  String get stockStatusInactive;

  /// No description provided for @refreshTooltip.
  ///
  /// In en, this message translates to:
  /// **'Refresh stock data'**
  String get refreshTooltip;

  /// No description provided for @viewSpecs.
  ///
  /// In en, this message translates to:
  /// **'View Details'**
  String get viewSpecs;

  /// No description provided for @itemDetails.
  ///
  /// In en, this message translates to:
  /// **'Product & Stock Details'**
  String get itemDetails;

  /// No description provided for @close.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get close;

  /// No description provided for @brand.
  ///
  /// In en, this message translates to:
  /// **'Brand'**
  String get brand;

  /// No description provided for @category.
  ///
  /// In en, this message translates to:
  /// **'Category'**
  String get category;

  /// No description provided for @mrpLabel.
  ///
  /// In en, this message translates to:
  /// **'MRP'**
  String get mrpLabel;

  /// No description provided for @purchaseRateLabel.
  ///
  /// In en, this message translates to:
  /// **'Purchase Rate'**
  String get purchaseRateLabel;

  /// No description provided for @taxRateLabel.
  ///
  /// In en, this message translates to:
  /// **'Tax Rate'**
  String get taxRateLabel;

  /// No description provided for @apply.
  ///
  /// In en, this message translates to:
  /// **'Apply Action'**
  String get apply;

  /// No description provided for @unitsLabel.
  ///
  /// In en, this message translates to:
  /// **'units'**
  String get unitsLabel;

  /// No description provided for @importPreviewTitle.
  ///
  /// In en, this message translates to:
  /// **'Import CSV Preview'**
  String get importPreviewTitle;

  /// No description provided for @barcodeDashboard.
  ///
  /// In en, this message translates to:
  /// **'Barcode Dashboard'**
  String get barcodeDashboard;

  /// No description provided for @barcodeSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Select eligible variants, preview thermal labels, and print or download.'**
  String get barcodeSubtitle;

  /// No description provided for @barcodePrinting.
  ///
  /// In en, this message translates to:
  /// **'Barcode Printing'**
  String get barcodePrinting;

  /// No description provided for @barcodeLookup.
  ///
  /// In en, this message translates to:
  /// **'Barcode Lookup'**
  String get barcodeLookup;

  /// No description provided for @totalVariants.
  ///
  /// In en, this message translates to:
  /// **'Total Variants'**
  String get totalVariants;

  /// No description provided for @barcodedItems.
  ///
  /// In en, this message translates to:
  /// **'Barcoded'**
  String get barcodedItems;

  /// No description provided for @missingBarcode.
  ///
  /// In en, this message translates to:
  /// **'Missing Barcode'**
  String get missingBarcode;

  /// No description provided for @printReady.
  ///
  /// In en, this message translates to:
  /// **'Print Ready'**
  String get printReady;

  /// No description provided for @findProductByBarcode.
  ///
  /// In en, this message translates to:
  /// **'Find a product by its saved barcode'**
  String get findProductByBarcode;

  /// No description provided for @typeOrScanBarcode.
  ///
  /// In en, this message translates to:
  /// **'Type or scan a barcode'**
  String get typeOrScanBarcode;

  /// No description provided for @barcodeNotFound.
  ///
  /// In en, this message translates to:
  /// **'Barcode not found'**
  String get barcodeNotFound;

  /// No description provided for @labelTemplate.
  ///
  /// In en, this message translates to:
  /// **'Label Template'**
  String get labelTemplate;

  /// No description provided for @labelSize.
  ///
  /// In en, this message translates to:
  /// **'Label Size'**
  String get labelSize;

  /// No description provided for @previewSelected.
  ///
  /// In en, this message translates to:
  /// **'Preview Selected'**
  String get previewSelected;

  /// No description provided for @downloadPdf.
  ///
  /// In en, this message translates to:
  /// **'Download PDF'**
  String get downloadPdf;

  /// No description provided for @printLabels.
  ///
  /// In en, this message translates to:
  /// **'Print Labels'**
  String get printLabels;

  /// No description provided for @selectAllVisible.
  ///
  /// In en, this message translates to:
  /// **'Select All Visible'**
  String get selectAllVisible;

  /// No description provided for @clearSelection.
  ///
  /// In en, this message translates to:
  /// **'Clear Selection'**
  String get clearSelection;

  /// No description provided for @showIneligible.
  ///
  /// In en, this message translates to:
  /// **'Show ineligible'**
  String get showIneligible;

  /// No description provided for @copiesForSelected.
  ///
  /// In en, this message translates to:
  /// **'Copies for selected'**
  String get copiesForSelected;

  /// No description provided for @verifiedStock.
  ///
  /// In en, this message translates to:
  /// **'Verified Stock'**
  String get verifiedStock;

  /// No description provided for @reportsNavTitle.
  ///
  /// In en, this message translates to:
  /// **'Reports & Analytics'**
  String get reportsNavTitle;

  /// No description provided for @oneClickAuditHeroTitle.
  ///
  /// In en, this message translates to:
  /// **'Automated Financial Reconciliation'**
  String get oneClickAuditHeroTitle;

  /// No description provided for @oneClickAuditHeroSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Review recorded sales, purchases, inventory, expenses and payroll with source evidence and disclosed limitations.'**
  String get oneClickAuditHeroSubtitle;

  /// No description provided for @launchCompleteAudit.
  ///
  /// In en, this message translates to:
  /// **'Generate reconciliation'**
  String get launchCompleteAudit;

  /// No description provided for @downloadAuditPdf.
  ///
  /// In en, this message translates to:
  /// **'Download review PDF'**
  String get downloadAuditPdf;

  /// No description provided for @downloadAuditExcel.
  ///
  /// In en, this message translates to:
  /// **'Export review Excel'**
  String get downloadAuditExcel;

  /// No description provided for @auditReportReady.
  ///
  /// In en, this message translates to:
  /// **'Review available'**
  String get auditReportReady;

  /// No description provided for @auditsAndStatutory.
  ///
  /// In en, this message translates to:
  /// **'Financial review and tax schedules'**
  String get auditsAndStatutory;

  /// No description provided for @completeAuditTileTitle.
  ///
  /// In en, this message translates to:
  /// **'Financial Reconciliation'**
  String get completeAuditTileTitle;

  /// No description provided for @completeAuditTileSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Source evidence, outlet consolidation and unresolved differences'**
  String get completeAuditTileSubtitle;

  /// No description provided for @financialYearPreset.
  ///
  /// In en, this message translates to:
  /// **'Financial Year'**
  String get financialYearPreset;

  /// No description provided for @statutoryComplianceBadge.
  ///
  /// In en, this message translates to:
  /// **'Evidence-based review'**
  String get statutoryComplianceBadge;

  /// No description provided for @turnoverGross.
  ///
  /// In en, this message translates to:
  /// **'Gross Turnover'**
  String get turnoverGross;

  /// No description provided for @costOfGoodsSold.
  ///
  /// In en, this message translates to:
  /// **'Cost of Goods Sold (COGS)'**
  String get costOfGoodsSold;

  /// No description provided for @grossProfitLabel.
  ///
  /// In en, this message translates to:
  /// **'Gross Profit'**
  String get grossProfitLabel;

  /// No description provided for @operatingExpensesLabel.
  ///
  /// In en, this message translates to:
  /// **'Operating Expenses'**
  String get operatingExpensesLabel;

  /// No description provided for @netProfitLabel.
  ///
  /// In en, this message translates to:
  /// **'Net Operating Profit (NPBT)'**
  String get netProfitLabel;

  /// No description provided for @workingCapitalLabel.
  ///
  /// In en, this message translates to:
  /// **'Net Working Capital'**
  String get workingCapitalLabel;

  /// No description provided for @languageSelector.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get languageSelector;

  /// No description provided for @english.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get english;

  /// No description provided for @hindi.
  ///
  /// In en, this message translates to:
  /// **'हिंदी (Hindi)'**
  String get hindi;

  /// No description provided for @bengali.
  ///
  /// In en, this message translates to:
  /// **'বাংলা (Bengali)'**
  String get bengali;

  /// No description provided for @selectLanguage.
  ///
  /// In en, this message translates to:
  /// **'Select Language'**
  String get selectLanguage;

  /// No description provided for @salesAndCollections.
  ///
  /// In en, this message translates to:
  /// **'Sales and collections'**
  String get salesAndCollections;

  /// No description provided for @purchasesAndInventory.
  ///
  /// In en, this message translates to:
  /// **'Purchases and inventory'**
  String get purchasesAndInventory;

  /// No description provided for @taxAndProfit.
  ///
  /// In en, this message translates to:
  /// **'Tax and profit'**
  String get taxAndProfit;

  /// No description provided for @productDashboardTitle.
  ///
  /// In en, this message translates to:
  /// **'Products & Catalogue'**
  String get productDashboardTitle;

  /// No description provided for @productDashboardSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Centralized catalogue, multi-variant specifications, pricing & outlet allocation'**
  String get productDashboardSubtitle;

  /// No description provided for @addProduct.
  ///
  /// In en, this message translates to:
  /// **'Add Product'**
  String get addProduct;

  /// No description provided for @addExistingToOutlet.
  ///
  /// In en, this message translates to:
  /// **'Add Existing to Outlet'**
  String get addExistingToOutlet;

  /// No description provided for @totalProducts.
  ///
  /// In en, this message translates to:
  /// **'Total Products'**
  String get totalProducts;

  /// No description provided for @activeProducts.
  ///
  /// In en, this message translates to:
  /// **'Active Products'**
  String get activeProducts;

  /// No description provided for @inactiveProducts.
  ///
  /// In en, this message translates to:
  /// **'Inactive Products'**
  String get inactiveProducts;

  /// No description provided for @stockAlerts.
  ///
  /// In en, this message translates to:
  /// **'Stock Alerts'**
  String get stockAlerts;

  /// No description provided for @searchProductPlaceholder.
  ///
  /// In en, this message translates to:
  /// **'Search product, brand, SKU, barcode, or category...'**
  String get searchProductPlaceholder;

  /// No description provided for @filterMultiVariant.
  ///
  /// In en, this message translates to:
  /// **'Multi-Variant'**
  String get filterMultiVariant;

  /// No description provided for @allBrands.
  ///
  /// In en, this message translates to:
  /// **'All Brands'**
  String get allBrands;

  /// No description provided for @allCategories.
  ///
  /// In en, this message translates to:
  /// **'All Categories'**
  String get allCategories;

  /// No description provided for @allSubcategories.
  ///
  /// In en, this message translates to:
  /// **'All Subcategories'**
  String get allSubcategories;

  /// No description provided for @allStatuses.
  ///
  /// In en, this message translates to:
  /// **'All Statuses'**
  String get allStatuses;

  /// No description provided for @statusActive.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get statusActive;

  /// No description provided for @statusInactive.
  ///
  /// In en, this message translates to:
  /// **'Inactive'**
  String get statusInactive;

  /// No description provided for @syncStatus.
  ///
  /// In en, this message translates to:
  /// **'Sync Status'**
  String get syncStatus;

  /// No description provided for @syncSynced.
  ///
  /// In en, this message translates to:
  /// **'Synced'**
  String get syncSynced;

  /// No description provided for @syncSyncing.
  ///
  /// In en, this message translates to:
  /// **'Syncing'**
  String get syncSyncing;

  /// No description provided for @syncPending.
  ///
  /// In en, this message translates to:
  /// **'Pending'**
  String get syncPending;

  /// No description provided for @syncError.
  ///
  /// In en, this message translates to:
  /// **'Sync Error'**
  String get syncError;

  /// No description provided for @actions.
  ///
  /// In en, this message translates to:
  /// **'Actions'**
  String get actions;

  /// No description provided for @viewProduct.
  ///
  /// In en, this message translates to:
  /// **'View Details'**
  String get viewProduct;

  /// No description provided for @editProduct.
  ///
  /// In en, this message translates to:
  /// **'Edit Product / Manage Variants'**
  String get editProduct;

  /// No description provided for @duplicateProduct.
  ///
  /// In en, this message translates to:
  /// **'Duplicate'**
  String get duplicateProduct;

  /// No description provided for @manageOutletAssignment.
  ///
  /// In en, this message translates to:
  /// **'Manage outlet assignment'**
  String get manageOutletAssignment;

  /// No description provided for @removeFromThisOutlet.
  ///
  /// In en, this message translates to:
  /// **'Remove from this outlet'**
  String get removeFromThisOutlet;

  /// No description provided for @activateInThisOutlet.
  ///
  /// In en, this message translates to:
  /// **'Activate in this outlet'**
  String get activateInThisOutlet;

  /// No description provided for @deleteProduct.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get deleteProduct;

  /// No description provided for @printBarcode.
  ///
  /// In en, this message translates to:
  /// **'Print Barcode'**
  String get printBarcode;

  /// No description provided for @editVariant.
  ///
  /// In en, this message translates to:
  /// **'Edit Variant'**
  String get editVariant;

  /// No description provided for @noProductsFound.
  ///
  /// In en, this message translates to:
  /// **'No products match your search.'**
  String get noProductsFound;

  /// No description provided for @noProductsOutletSubtitle.
  ///
  /// In en, this message translates to:
  /// **'No Products are assigned to this outlet. Add a new Product.'**
  String get noProductsOutletSubtitle;

  /// No description provided for @noProductsFoundSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Try adjusting your search keywords or filter status.'**
  String get noProductsFoundSubtitle;

  /// No description provided for @deleteProductsConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete products?'**
  String get deleteProductsConfirmTitle;

  /// No description provided for @deleteProductsConfirmMessage.
  ///
  /// In en, this message translates to:
  /// **'Products will be archived. Historical transactions and variants will be preserved.'**
  String get deleteProductsConfirmMessage;

  /// No description provided for @changeStatusConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Change product status?'**
  String get changeStatusConfirmTitle;

  /// No description provided for @businessDashboardTitle.
  ///
  /// In en, this message translates to:
  /// **'Business & Organization Workspace'**
  String get businessDashboardTitle;

  /// No description provided for @businessDashboardSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Choose a business to continue. Your businesses stay separate.'**
  String get businessDashboardSubtitle;

  /// No description provided for @selectBusiness.
  ///
  /// In en, this message translates to:
  /// **'Select a business'**
  String get selectBusiness;

  /// No description provided for @addBusiness.
  ///
  /// In en, this message translates to:
  /// **'Add business'**
  String get addBusiness;

  /// No description provided for @totalBusinesses.
  ///
  /// In en, this message translates to:
  /// **'Total Businesses'**
  String get totalBusinesses;

  /// No description provided for @activeBusinesses.
  ///
  /// In en, this message translates to:
  /// **'Active Businesses'**
  String get activeBusinesses;

  /// No description provided for @searchBusinessesPlaceholder.
  ///
  /// In en, this message translates to:
  /// **'Search by business name, GSTIN, type, or address...'**
  String get searchBusinessesPlaceholder;

  /// No description provided for @noBusinessesFound.
  ///
  /// In en, this message translates to:
  /// **'No businesses found'**
  String get noBusinessesFound;

  /// No description provided for @noBusinessesFoundSubtitle.
  ///
  /// In en, this message translates to:
  /// **'There are no active businesses available for this account.'**
  String get noBusinessesFoundSubtitle;

  /// No description provided for @openWorkspace.
  ///
  /// In en, this message translates to:
  /// **'Open Workspace'**
  String get openWorkspace;

  /// No description provided for @enterStore.
  ///
  /// In en, this message translates to:
  /// **'Enter Store'**
  String get enterStore;

  /// No description provided for @outletDashboardTitle.
  ///
  /// In en, this message translates to:
  /// **'Outlet & Store Workspace'**
  String get outletDashboardTitle;

  /// No description provided for @outletDashboardSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Choose an outlet to continue store billing, stock & inventory operations.'**
  String get outletDashboardSubtitle;

  /// No description provided for @selectOutlet.
  ///
  /// In en, this message translates to:
  /// **'Select an outlet'**
  String get selectOutlet;

  /// No description provided for @addOutlet.
  ///
  /// In en, this message translates to:
  /// **'Add outlet'**
  String get addOutlet;

  /// No description provided for @searchOutletsPlaceholder.
  ///
  /// In en, this message translates to:
  /// **'Search by outlet name, code, type, or address...'**
  String get searchOutletsPlaceholder;

  /// No description provided for @noOutletsFound.
  ///
  /// In en, this message translates to:
  /// **'No Outlet Available'**
  String get noOutletsFound;

  /// No description provided for @noOutletsFoundSubtitle.
  ///
  /// In en, this message translates to:
  /// **'This Business has no active Outlets yet. Add an Outlet to continue.'**
  String get noOutletsFoundSubtitle;

  /// No description provided for @createBusinessTitle.
  ///
  /// In en, this message translates to:
  /// **'Create your business'**
  String get createBusinessTitle;

  /// No description provided for @createBusinessSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Add the business profile. You can create more businesses later.'**
  String get createBusinessSubtitle;

  /// No description provided for @createOutletTitle.
  ///
  /// In en, this message translates to:
  /// **'Add Outlet'**
  String get createOutletTitle;

  /// No description provided for @createOutletSubtitle.
  ///
  /// In en, this message translates to:
  /// **'This outlet belongs to the selected business.'**
  String get createOutletSubtitle;

  /// No description provided for @businessNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Business Name *'**
  String get businessNameLabel;

  /// No description provided for @businessEmailLabel.
  ///
  /// In en, this message translates to:
  /// **'Business Email *'**
  String get businessEmailLabel;

  /// No description provided for @businessPhoneLabel.
  ///
  /// In en, this message translates to:
  /// **'Business Contact Number *'**
  String get businessPhoneLabel;

  /// No description provided for @businessAddressLabel.
  ///
  /// In en, this message translates to:
  /// **'Business Address *'**
  String get businessAddressLabel;

  /// No description provided for @outletNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Outlet Name *'**
  String get outletNameLabel;

  /// No description provided for @outletAddressLabel.
  ///
  /// In en, this message translates to:
  /// **'Outlet Address *'**
  String get outletAddressLabel;

  /// No description provided for @outletContactNumberLabel.
  ///
  /// In en, this message translates to:
  /// **'Contact Number *'**
  String get outletContactNumberLabel;

  /// No description provided for @outletCodeNotice.
  ///
  /// In en, this message translates to:
  /// **'Outlet Code: Auto-generated when saved'**
  String get outletCodeNotice;

  /// No description provided for @gstinOptionalLabel.
  ///
  /// In en, this message translates to:
  /// **'GSTIN (optional)'**
  String get gstinOptionalLabel;

  /// No description provided for @saveBusiness.
  ///
  /// In en, this message translates to:
  /// **'Create Business'**
  String get saveBusiness;

  /// No description provided for @saveOutlet.
  ///
  /// In en, this message translates to:
  /// **'Save Outlet'**
  String get saveOutlet;

  /// No description provided for @discardChangesTitle.
  ///
  /// In en, this message translates to:
  /// **'Discard Changes?'**
  String get discardChangesTitle;

  /// No description provided for @discardChangesSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Your entered information will be lost.'**
  String get discardChangesSubtitle;

  /// No description provided for @discard.
  ///
  /// In en, this message translates to:
  /// **'Discard'**
  String get discard;

  /// No description provided for @expensesDashboardTitle.
  ///
  /// In en, this message translates to:
  /// **'Expenses & Outflows'**
  String get expensesDashboardTitle;

  /// No description provided for @expensesDashboardSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Track operational overheads, store upkeep, utilities, salaries, and petty cash'**
  String get expensesDashboardSubtitle;

  /// No description provided for @customDateRange.
  ///
  /// In en, this message translates to:
  /// **'Custom range'**
  String get customDateRange;

  /// No description provided for @sortDateNewest.
  ///
  /// In en, this message translates to:
  /// **'Date: Newest'**
  String get sortDateNewest;

  /// No description provided for @sortDateOldest.
  ///
  /// In en, this message translates to:
  /// **'Date: Oldest'**
  String get sortDateOldest;

  /// No description provided for @sortAmountHighLow.
  ///
  /// In en, this message translates to:
  /// **'Amount: High to low'**
  String get sortAmountHighLow;

  /// No description provided for @sortAmountLowHigh.
  ///
  /// In en, this message translates to:
  /// **'Amount: Low to high'**
  String get sortAmountLowHigh;

  /// No description provided for @sortTitleAz.
  ///
  /// In en, this message translates to:
  /// **'Title: A to Z'**
  String get sortTitleAz;

  /// No description provided for @filtered.
  ///
  /// In en, this message translates to:
  /// **'Filtered'**
  String get filtered;

  /// No description provided for @recordExpense.
  ///
  /// In en, this message translates to:
  /// **'Record Expense'**
  String get recordExpense;

  /// No description provided for @newExpenseVoucher.
  ///
  /// In en, this message translates to:
  /// **'New Expense Voucher'**
  String get newExpenseVoucher;

  /// No description provided for @todayExpenses.
  ///
  /// In en, this message translates to:
  /// **'Today\'s Expense'**
  String get todayExpenses;

  /// No description provided for @thisMonthExpenses.
  ///
  /// In en, this message translates to:
  /// **'This Month\'s Total'**
  String get thisMonthExpenses;

  /// No description provided for @cashOutflow.
  ///
  /// In en, this message translates to:
  /// **'Cash Outflow'**
  String get cashOutflow;

  /// No description provided for @digitalOutflow.
  ///
  /// In en, this message translates to:
  /// **'Digital & Bank'**
  String get digitalOutflow;

  /// No description provided for @activeVouchers.
  ///
  /// In en, this message translates to:
  /// **'Active Records'**
  String get activeVouchers;

  /// No description provided for @activeDisbursementsToday.
  ///
  /// In en, this message translates to:
  /// **'Disbursements today'**
  String get activeDisbursementsToday;

  /// No description provided for @currentBillingPeriod.
  ///
  /// In en, this message translates to:
  /// **'Current billing period'**
  String get currentBillingPeriod;

  /// No description provided for @disbursedFromTill.
  ///
  /// In en, this message translates to:
  /// **'From cash till'**
  String get disbursedFromTill;

  /// No description provided for @digitalAndBankSubtitle.
  ///
  /// In en, this message translates to:
  /// **'UPI, Bank, Card & Cheque'**
  String get digitalAndBankSubtitle;

  /// No description provided for @totalExpenseVouchers.
  ///
  /// In en, this message translates to:
  /// **'Total expense vouchers'**
  String get totalExpenseVouchers;

  /// No description provided for @searchExpensesPlaceholder.
  ///
  /// In en, this message translates to:
  /// **'Search by title, payee, voucher #, notes...'**
  String get searchExpensesPlaceholder;

  /// No description provided for @periodFilter.
  ///
  /// In en, this message translates to:
  /// **'Period'**
  String get periodFilter;

  /// No description provided for @filterPeriodToday.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get filterPeriodToday;

  /// No description provided for @filterPeriodThisWeek.
  ///
  /// In en, this message translates to:
  /// **'This Week'**
  String get filterPeriodThisWeek;

  /// No description provided for @filterPeriodThisMonth.
  ///
  /// In en, this message translates to:
  /// **'This Month'**
  String get filterPeriodThisMonth;

  /// No description provided for @filterPeriodThisQuarter.
  ///
  /// In en, this message translates to:
  /// **'This Quarter'**
  String get filterPeriodThisQuarter;

  /// No description provided for @filterPeriodAllTime.
  ///
  /// In en, this message translates to:
  /// **'All Time'**
  String get filterPeriodAllTime;

  /// No description provided for @categoryFilter.
  ///
  /// In en, this message translates to:
  /// **'Category'**
  String get categoryFilter;

  /// No description provided for @paymentModeFilter.
  ///
  /// In en, this message translates to:
  /// **'Payment Mode'**
  String get paymentModeFilter;

  /// No description provided for @allPaymentModes.
  ///
  /// In en, this message translates to:
  /// **'All Modes'**
  String get allPaymentModes;

  /// No description provided for @paymentModeCash.
  ///
  /// In en, this message translates to:
  /// **'Cash'**
  String get paymentModeCash;

  /// No description provided for @paymentModeUpi.
  ///
  /// In en, this message translates to:
  /// **'UPI'**
  String get paymentModeUpi;

  /// No description provided for @paymentModeBankTransfer.
  ///
  /// In en, this message translates to:
  /// **'Bank Transfer'**
  String get paymentModeBankTransfer;

  /// No description provided for @paymentModeCheque.
  ///
  /// In en, this message translates to:
  /// **'Cheque'**
  String get paymentModeCheque;

  /// No description provided for @paymentModeCard.
  ///
  /// In en, this message translates to:
  /// **'Card'**
  String get paymentModeCard;

  /// No description provided for @statusFilter.
  ///
  /// In en, this message translates to:
  /// **'Status'**
  String get statusFilter;

  /// No description provided for @statusAll.
  ///
  /// In en, this message translates to:
  /// **'All Status'**
  String get statusAll;

  /// No description provided for @statusVoided.
  ///
  /// In en, this message translates to:
  /// **'Voided'**
  String get statusVoided;

  /// No description provided for @dateTime.
  ///
  /// In en, this message translates to:
  /// **'Date & Time'**
  String get dateTime;

  /// No description provided for @titleOrDescription.
  ///
  /// In en, this message translates to:
  /// **'Title / Description'**
  String get titleOrDescription;

  /// No description provided for @payee.
  ///
  /// In en, this message translates to:
  /// **'Payee / Paid To'**
  String get payee;

  /// No description provided for @refVoucherNumber.
  ///
  /// In en, this message translates to:
  /// **'Ref / Voucher #'**
  String get refVoucherNumber;

  /// No description provided for @amountRupees.
  ///
  /// In en, this message translates to:
  /// **'Amount'**
  String get amountRupees;

  /// No description provided for @voidExpense.
  ///
  /// In en, this message translates to:
  /// **'Void Expense'**
  String get voidExpense;

  /// No description provided for @voidExpenseConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Void Expense Voucher?'**
  String get voidExpenseConfirmTitle;

  /// No description provided for @voidExpenseConfirmMessage.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to void this expense? This action will mark it as VOIDED and exclude it from active totals.'**
  String get voidExpenseConfirmMessage;

  /// No description provided for @expenseVoidedSuccess.
  ///
  /// In en, this message translates to:
  /// **'Expense voucher voided successfully.'**
  String get expenseVoidedSuccess;

  /// No description provided for @expenseSavedSuccess.
  ///
  /// In en, this message translates to:
  /// **'Expense voucher recorded successfully.'**
  String get expenseSavedSuccess;

  /// No description provided for @spendingByCategory.
  ///
  /// In en, this message translates to:
  /// **'Spending by Category'**
  String get spendingByCategory;

  /// No description provided for @noExpensesFound.
  ///
  /// In en, this message translates to:
  /// **'No expense records found'**
  String get noExpensesFound;

  /// No description provided for @noExpensesSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Record operational overheads, utilities, or petty cash to start tracking'**
  String get noExpensesSubtitle;

  /// No description provided for @noExpensesMatchingFilters.
  ///
  /// In en, this message translates to:
  /// **'No expense vouchers match your active filters.'**
  String get noExpensesMatchingFilters;

  /// No description provided for @clearAllFilters.
  ///
  /// In en, this message translates to:
  /// **'Clear Filters'**
  String get clearAllFilters;

  /// No description provided for @expenseDetails.
  ///
  /// In en, this message translates to:
  /// **'Expense Voucher Details'**
  String get expenseDetails;

  /// No description provided for @auditInfo.
  ///
  /// In en, this message translates to:
  /// **'Audit Information'**
  String get auditInfo;

  /// No description provided for @voucherDetails.
  ///
  /// In en, this message translates to:
  /// **'Voucher Details'**
  String get voucherDetails;

  /// No description provided for @saveExpense.
  ///
  /// In en, this message translates to:
  /// **'Save Expense'**
  String get saveExpense;

  /// No description provided for @amountRequiredError.
  ///
  /// In en, this message translates to:
  /// **'Amount is required and must be greater than zero.'**
  String get amountRequiredError;

  /// No description provided for @descriptionRequiredError.
  ///
  /// In en, this message translates to:
  /// **'Description / Title is required.'**
  String get descriptionRequiredError;

  /// No description provided for @quickAddAmount.
  ///
  /// In en, this message translates to:
  /// **'Quick Amount'**
  String get quickAddAmount;

  /// No description provided for @suggestions.
  ///
  /// In en, this message translates to:
  /// **'Suggestions'**
  String get suggestions;

  /// No description provided for @printVoucher.
  ///
  /// In en, this message translates to:
  /// **'Print Voucher'**
  String get printVoucher;

  /// No description provided for @expenseDate.
  ///
  /// In en, this message translates to:
  /// **'Expense Date'**
  String get expenseDate;

  /// No description provided for @remarksOrNotes.
  ///
  /// In en, this message translates to:
  /// **'Remarks / Notes'**
  String get remarksOrNotes;

  /// No description provided for @createdBy.
  ///
  /// In en, this message translates to:
  /// **'Created By'**
  String get createdBy;

  /// No description provided for @customerDashboard.
  ///
  /// In en, this message translates to:
  /// **'Customer Hub'**
  String get customerDashboard;

  /// No description provided for @customerDashboardSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Manage customer profiles, credit limits, outstanding receivables, and instant UPI collection.'**
  String get customerDashboardSubtitle;

  /// No description provided for @totalCustomers.
  ///
  /// In en, this message translates to:
  /// **'Total Customers'**
  String get totalCustomers;

  /// No description provided for @totalDueReceivable.
  ///
  /// In en, this message translates to:
  /// **'Total Due Receivable'**
  String get totalDueReceivable;

  /// No description provided for @totalAdvanceReceived.
  ///
  /// In en, this message translates to:
  /// **'Total Advance Received'**
  String get totalAdvanceReceived;

  /// No description provided for @creditExtended.
  ///
  /// In en, this message translates to:
  /// **'Credit Extended'**
  String get creditExtended;

  /// No description provided for @registeredAccounts.
  ///
  /// In en, this message translates to:
  /// **'Registered accounts'**
  String get registeredAccounts;

  /// No description provided for @accountsWithDue.
  ///
  /// In en, this message translates to:
  /// **'Accounts with due'**
  String get accountsWithDue;

  /// No description provided for @accountsWithAdvance.
  ///
  /// In en, this message translates to:
  /// **'Accounts with advance'**
  String get accountsWithAdvance;

  /// No description provided for @activeCreditLines.
  ///
  /// In en, this message translates to:
  /// **'Active credit lines'**
  String get activeCreditLines;

  /// No description provided for @sortCustomers.
  ///
  /// In en, this message translates to:
  /// **'Sort customers'**
  String get sortCustomers;

  /// No description provided for @sortSuppliers.
  ///
  /// In en, this message translates to:
  /// **'Sort suppliers'**
  String get sortSuppliers;

  /// No description provided for @dueHighToLow.
  ///
  /// In en, this message translates to:
  /// **'Due: High to low'**
  String get dueHighToLow;

  /// No description provided for @advanceHighToLow.
  ///
  /// In en, this message translates to:
  /// **'Advance: High to low'**
  String get advanceHighToLow;

  /// No description provided for @nameAToZ.
  ///
  /// In en, this message translates to:
  /// **'Name: A to Z'**
  String get nameAToZ;

  /// No description provided for @nameZToA.
  ///
  /// In en, this message translates to:
  /// **'Name: Z to A'**
  String get nameZToA;

  /// No description provided for @linkedToBusiness.
  ///
  /// In en, this message translates to:
  /// **'Linked to business'**
  String get linkedToBusiness;

  /// No description provided for @readyForPurchases.
  ///
  /// In en, this message translates to:
  /// **'Ready for purchases'**
  String get readyForPurchases;

  /// No description provided for @deactivatedAccounts.
  ///
  /// In en, this message translates to:
  /// **'Deactivated accounts'**
  String get deactivatedAccounts;

  /// No description provided for @availableToLink.
  ///
  /// In en, this message translates to:
  /// **'Available to link'**
  String get availableToLink;

  /// No description provided for @fromOtherBusinesses.
  ///
  /// In en, this message translates to:
  /// **'From other businesses'**
  String get fromOtherBusinesses;

  /// No description provided for @allCustomers.
  ///
  /// In en, this message translates to:
  /// **'All Customers'**
  String get allCustomers;

  /// No description provided for @hasDue.
  ///
  /// In en, this message translates to:
  /// **'Has Due'**
  String get hasDue;

  /// No description provided for @hasAdvance.
  ///
  /// In en, this message translates to:
  /// **'Has Advance'**
  String get hasAdvance;

  /// No description provided for @settled.
  ///
  /// In en, this message translates to:
  /// **'Settled'**
  String get settled;

  /// No description provided for @searchCustomers.
  ///
  /// In en, this message translates to:
  /// **'Search customers'**
  String get searchCustomers;

  /// No description provided for @searchCustomersPlaceholder.
  ///
  /// In en, this message translates to:
  /// **'Search by customer name, phone, GSTIN, or city...'**
  String get searchCustomersPlaceholder;

  /// No description provided for @addCustomer.
  ///
  /// In en, this message translates to:
  /// **'Add Customer'**
  String get addCustomer;

  /// No description provided for @editCustomer.
  ///
  /// In en, this message translates to:
  /// **'Edit Customer'**
  String get editCustomer;

  /// No description provided for @customerSaved.
  ///
  /// In en, this message translates to:
  /// **'Customer saved locally and queued for background sync.'**
  String get customerSaved;

  /// No description provided for @customerUpdated.
  ///
  /// In en, this message translates to:
  /// **'Customer details updated successfully.'**
  String get customerUpdated;

  /// No description provided for @noCustomersFound.
  ///
  /// In en, this message translates to:
  /// **'No customers found'**
  String get noCustomersFound;

  /// No description provided for @noCustomersFoundSubtitle.
  ///
  /// In en, this message translates to:
  /// **'No customer profiles match your search criteria.'**
  String get noCustomersFoundSubtitle;

  /// No description provided for @noCustomersYet.
  ///
  /// In en, this message translates to:
  /// **'No customers saved yet'**
  String get noCustomersYet;

  /// No description provided for @noCustomersYetSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Add your first customer to track sales, ledger dues, and contact details.'**
  String get noCustomersYetSubtitle;

  /// No description provided for @showUpiQr.
  ///
  /// In en, this message translates to:
  /// **'Show UPI QR to collect due'**
  String get showUpiQr;

  /// No description provided for @upiCollect.
  ///
  /// In en, this message translates to:
  /// **'UPI Collect'**
  String get upiCollect;

  /// No description provided for @creditLimit.
  ///
  /// In en, this message translates to:
  /// **'Credit Limit'**
  String get creditLimit;

  /// No description provided for @openingBalance.
  ///
  /// In en, this message translates to:
  /// **'Opening Balance'**
  String get openingBalance;

  /// No description provided for @openingBalanceHelper.
  ///
  /// In en, this message translates to:
  /// **'Positive = customer owes you (Due), Negative = advance received'**
  String get openingBalanceHelper;

  /// No description provided for @currentBalance.
  ///
  /// In en, this message translates to:
  /// **'Current Balance'**
  String get currentBalance;

  /// No description provided for @customerName.
  ///
  /// In en, this message translates to:
  /// **'Customer Name'**
  String get customerName;

  /// No description provided for @stateCode.
  ///
  /// In en, this message translates to:
  /// **'State Code'**
  String get stateCode;

  /// No description provided for @billingAddress.
  ///
  /// In en, this message translates to:
  /// **'Billing Address'**
  String get billingAddress;

  /// No description provided for @supplierDashboard.
  ///
  /// In en, this message translates to:
  /// **'Supplier & Vendor Hub'**
  String get supplierDashboard;

  /// No description provided for @supplierDashboardSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Oversee procurement partners, trade credit terms, advance balances, and refunds.'**
  String get supplierDashboardSubtitle;

  /// No description provided for @totalSuppliers.
  ///
  /// In en, this message translates to:
  /// **'Total Suppliers'**
  String get totalSuppliers;

  /// No description provided for @activeSuppliers.
  ///
  /// In en, this message translates to:
  /// **'Active Suppliers'**
  String get activeSuppliers;

  /// No description provided for @inactiveSuppliers.
  ///
  /// In en, this message translates to:
  /// **'Inactive Suppliers'**
  String get inactiveSuppliers;

  /// No description provided for @totalSupplierAdvance.
  ///
  /// In en, this message translates to:
  /// **'Available Advance'**
  String get totalSupplierAdvance;

  /// No description provided for @preferredSuppliers.
  ///
  /// In en, this message translates to:
  /// **'Preferred Partners'**
  String get preferredSuppliers;

  /// No description provided for @addSupplier.
  ///
  /// In en, this message translates to:
  /// **'Add Supplier'**
  String get addSupplier;

  /// No description provided for @editSupplier.
  ///
  /// In en, this message translates to:
  /// **'Edit Supplier'**
  String get editSupplier;

  /// No description provided for @linkExistingSupplier.
  ///
  /// In en, this message translates to:
  /// **'Link Existing Supplier'**
  String get linkExistingSupplier;

  /// No description provided for @searchSuppliers.
  ///
  /// In en, this message translates to:
  /// **'Search suppliers'**
  String get searchSuppliers;

  /// No description provided for @searchSuppliersPlaceholder.
  ///
  /// In en, this message translates to:
  /// **'Search by supplier name, contact person, mobile, or GSTIN...'**
  String get searchSuppliersPlaceholder;

  /// No description provided for @noSuppliersFound.
  ///
  /// In en, this message translates to:
  /// **'No suppliers found'**
  String get noSuppliersFound;

  /// No description provided for @noSuppliersFoundSubtitle.
  ///
  /// In en, this message translates to:
  /// **'No supplier profiles match your search criteria.'**
  String get noSuppliersFoundSubtitle;

  /// No description provided for @noSuppliersYet.
  ///
  /// In en, this message translates to:
  /// **'No suppliers linked yet'**
  String get noSuppliersYet;

  /// No description provided for @noSuppliersYetSubtitle.
  ///
  /// In en, this message translates to:
  /// **'No suppliers are linked to this business. Add a supplier or link one from another business.'**
  String get noSuppliersYetSubtitle;

  /// No description provided for @availableAdvance.
  ///
  /// In en, this message translates to:
  /// **'Available Advance'**
  String get availableAdvance;

  /// No description provided for @recordRefund.
  ///
  /// In en, this message translates to:
  /// **'Record Refund'**
  String get recordRefund;

  /// No description provided for @supplierAdvance.
  ///
  /// In en, this message translates to:
  /// **'Supplier Advance'**
  String get supplierAdvance;

  /// No description provided for @businessTerms.
  ///
  /// In en, this message translates to:
  /// **'Business Terms'**
  String get businessTerms;

  /// No description provided for @optionalBusinessTerms.
  ///
  /// In en, this message translates to:
  /// **'Optional Business Terms'**
  String get optionalBusinessTerms;

  /// No description provided for @optionalBusinessTermsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Configure commercial terms now, or leave them at zero and update them later.'**
  String get optionalBusinessTermsSubtitle;

  /// No description provided for @paymentTermsDays.
  ///
  /// In en, this message translates to:
  /// **'Payment Terms (days)'**
  String get paymentTermsDays;

  /// No description provided for @openingPayable.
  ///
  /// In en, this message translates to:
  /// **'Opening Payable'**
  String get openingPayable;

  /// No description provided for @openingPayableHelper.
  ///
  /// In en, this message translates to:
  /// **'Opening payable is recorded in the ledger and cannot be edited here.'**
  String get openingPayableHelper;

  /// No description provided for @preferredSupplier.
  ///
  /// In en, this message translates to:
  /// **'Preferred Supplier'**
  String get preferredSupplier;

  /// No description provided for @preferredSupplierSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Used as a supplier indicator only.'**
  String get preferredSupplierSubtitle;

  /// No description provided for @contactPerson.
  ///
  /// In en, this message translates to:
  /// **'Contact Person'**
  String get contactPerson;

  /// No description provided for @supplierMobile.
  ///
  /// In en, this message translates to:
  /// **'Mobile Number'**
  String get supplierMobile;

  /// No description provided for @supplierEmail.
  ///
  /// In en, this message translates to:
  /// **'Email Address'**
  String get supplierEmail;

  /// No description provided for @whatsappNumber.
  ///
  /// In en, this message translates to:
  /// **'WhatsApp Number'**
  String get whatsappNumber;

  /// No description provided for @panNumber.
  ///
  /// In en, this message translates to:
  /// **'PAN Number'**
  String get panNumber;

  /// No description provided for @supplierType.
  ///
  /// In en, this message translates to:
  /// **'Supplier Type / Category'**
  String get supplierType;

  /// No description provided for @supplierSaved.
  ///
  /// In en, this message translates to:
  /// **'Supplier saved successfully and queued for sync.'**
  String get supplierSaved;

  /// No description provided for @supplierUpdated.
  ///
  /// In en, this message translates to:
  /// **'Supplier updated successfully.'**
  String get supplierUpdated;

  /// No description provided for @logoutConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Log out?'**
  String get logoutConfirmTitle;

  /// No description provided for @logoutConfirmMessage.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to log out of your account? Any unsaved changes in progress may be lost.'**
  String get logoutConfirmMessage;

  /// No description provided for @aboutAppTitle.
  ///
  /// In en, this message translates to:
  /// **'About NubiBill Business ERP'**
  String get aboutAppTitle;

  /// No description provided for @aboutAppSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Enterprise Multi-Outlet Retail & Wholesale ERP System'**
  String get aboutAppSubtitle;

  /// No description provided for @companyWebsite.
  ///
  /// In en, this message translates to:
  /// **'Official Website'**
  String get companyWebsite;

  /// No description provided for @documentation.
  ///
  /// In en, this message translates to:
  /// **'Documentation & User Guide'**
  String get documentation;

  /// No description provided for @technicalSupport.
  ///
  /// In en, this message translates to:
  /// **'Technical Support'**
  String get technicalSupport;

  /// No description provided for @privacyPolicy.
  ///
  /// In en, this message translates to:
  /// **'Privacy Policy'**
  String get privacyPolicy;

  /// No description provided for @termsOfService.
  ///
  /// In en, this message translates to:
  /// **'Terms of Service'**
  String get termsOfService;

  /// No description provided for @aboutAppDescription.
  ///
  /// In en, this message translates to:
  /// **'High-performance, offline-first enterprise management solution engineered for retail, wholesale, godown logistics, and commercial trade operations.'**
  String get aboutAppDescription;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['bn', 'en', 'hi'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'bn':
      return AppLocalizationsBn();
    case 'en':
      return AppLocalizationsEn();
    case 'hi':
      return AppLocalizationsHi();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
