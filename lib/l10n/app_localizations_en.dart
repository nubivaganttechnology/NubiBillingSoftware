// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'NubiBill ERP';

  @override
  String get workspace => 'WORKSPACE';

  @override
  String get dashboard => 'Dashboard';

  @override
  String get billing => 'POS Billing';

  @override
  String get sales => 'Sales';

  @override
  String get purchases => 'Purchases';

  @override
  String get products => 'Products';

  @override
  String get godowns => 'Godowns';

  @override
  String get racks => 'Racks';

  @override
  String get barcode => 'Barcode';

  @override
  String get customers => 'Customers';

  @override
  String get suppliers => 'Suppliers';

  @override
  String get expenses => 'Expenses';

  @override
  String get staffRoles => 'Staff & Roles';

  @override
  String get settings => 'Settings';

  @override
  String get businesses => 'Businesses';

  @override
  String get logout => 'Log out';

  @override
  String get business => 'Business';

  @override
  String get outlet => 'Outlet';

  @override
  String get searchWorkspace => 'Search workspace';

  @override
  String get switchBusiness => 'Switch business';

  @override
  String get switchOutlet => 'Switch outlet';

  @override
  String get syncStatusSynced => 'Synced';

  @override
  String get syncStatusSyncing => 'Syncing';

  @override
  String get syncStatusOffline => 'Offline';

  @override
  String get syncStatusPending => 'Pending';

  @override
  String get syncStatusError => 'Sync error';

  @override
  String get refresh => 'Refresh';

  @override
  String get language => 'Language';

  @override
  String get totalSales => 'Total sales';

  @override
  String get totalPurchases => 'Total purchases';

  @override
  String get borrowed => 'Borrowed';

  @override
  String get collected => 'Collected';

  @override
  String get payable => 'Payable';

  @override
  String get active => 'Active';

  @override
  String get inactive => 'Inactive';

  @override
  String get outOfStock => 'Out of Stock';

  @override
  String get lowStock => 'Low Stock';

  @override
  String get records => 'records';

  @override
  String get allSettled => 'All settled';

  @override
  String get withDues => 'with dues';

  @override
  String get liquidityVelocityTitle =>
      'Commercial Liquidity & Cashflow Velocity';

  @override
  String get net => 'Net';

  @override
  String get realizedCash => 'Realized Cash';

  @override
  String get borrowedUdhaar => 'Borrowed (Udhaar)';

  @override
  String get vendorPayables => 'Vendor Payables';

  @override
  String get inventoryHealthTitle => 'Inventory Health & Stock Intelligence';

  @override
  String get inventorySubtitle =>
      'Real-time store catalog distribution and replenishment alerts';

  @override
  String get optimalHealth => 'Optimal Health';

  @override
  String get manageCatalog => 'Manage Catalog';

  @override
  String get activeInStore => 'Active in Store';

  @override
  String get inactiveHidden => 'Inactive / Hidden';

  @override
  String get lowStockAlerts => 'Low Stock Alerts';

  @override
  String get catalogActiveItems => 'Catalog active items';

  @override
  String get draftOrArchived => 'Draft or archived';

  @override
  String get zeroUnitsRemaining => '0 units remaining';

  @override
  String get belowReorderLevel => 'Below reorder level';

  @override
  String get actionNeededReorder => 'Action Needed: Reorder List';

  @override
  String get inwardNewPurchase => 'Inward / New Purchase';

  @override
  String get inward => 'Inward';

  @override
  String get reorder => 'Reorder';

  @override
  String get allStockSufficient =>
      'All inventory products are sufficiently stocked above reorder thresholds.';

  @override
  String get posBillingTerminal => 'POS Billing Terminal';

  @override
  String get newBill => 'New Bill';

  @override
  String get selectOutletBeforeBilling => 'Select an outlet before billing.';

  @override
  String get gst => 'GST';

  @override
  String get nonGst => 'Non-GST';

  @override
  String get customerGstin => 'Customer GSTIN (optional)';

  @override
  String get customerGstinHint => 'Enter GSTIN for this GST bill';

  @override
  String get walkInCustomer => 'Walk-in Customer';

  @override
  String get selectCustomer => 'Select Customer';

  @override
  String get change => 'Change';

  @override
  String get scanBarcodeOrSearch => 'Scan barcode or search name/SKU';

  @override
  String get scanBarcodeLabel => 'Scan barcode / Search product';

  @override
  String get qty => 'Qty';

  @override
  String get discount => 'Discount';

  @override
  String get addToCart => 'Add to Cart';

  @override
  String get addAnotherProduct => 'Add another product';

  @override
  String get clearCart => 'Clear Cart';

  @override
  String get cartEmpty => 'No items in this bill.';

  @override
  String get cartEmptySubtitle =>
      'Scan a barcode or search products above to start billing.';

  @override
  String get sku => 'SKU';

  @override
  String get name => 'Name';

  @override
  String get price => 'Price';

  @override
  String get taxable => 'Taxable';

  @override
  String get total => 'Total';

  @override
  String get action => 'Action';

  @override
  String get subtotal => 'Subtotal';

  @override
  String get cgstSgst => 'CGST + SGST';

  @override
  String get gstTurnedOff => 'GST (Turned off)';

  @override
  String get roundOff => 'Round off';

  @override
  String get grandTotal => 'Grand Total';

  @override
  String get billGstRate => 'Bill GST Rate (Apply to all):';

  @override
  String get customPercent => 'Custom %';

  @override
  String get paymentOption => 'PAYMENT OPTION';

  @override
  String get paymentModeFullCash => 'Full Cash';

  @override
  String get paymentModeFullUpi => 'Full UPI';

  @override
  String get paymentModeSplit => 'Partial Cash & UPI';

  @override
  String get paymentModeUdhaar => 'Borrow (Credit / Udhaar)';

  @override
  String get collectFullCash => 'Collect Full Cash';

  @override
  String get cashReceived => 'Cash received from customer (₹)';

  @override
  String get changeToReturn => 'Change to return';

  @override
  String get shortBy => 'Short by';

  @override
  String get collectFullUpi => 'Collect Full Amount via UPI';

  @override
  String get showDynamicUpiQr => 'Show Dynamic UPI QR';

  @override
  String get cashAmount => 'Cash Amount (₹)';

  @override
  String get upiAmount => 'UPI Amount (₹)';

  @override
  String get setRemainderToCash => 'Set remainder to Cash';

  @override
  String get setRemainderToUpi => 'Set remainder to UPI';

  @override
  String get showUpiQrFor => 'Show UPI QR for';

  @override
  String get fullAmountAllocated => 'Full amount allocated (Cash + UPI)';

  @override
  String get remainingToAllocate => 'Remaining to allocate';

  @override
  String get borrowRequiresCustomer => 'Borrow requires customer selection';

  @override
  String get selectAddCustomer => 'Select / Add Customer';

  @override
  String get cashDownPayment => 'Cash Down Payment (Optional)';

  @override
  String get upiDownPayment => 'UPI Down Payment (Optional)';

  @override
  String get setRepaymentDueDate => 'Set Repayment Due Date (Optional)';

  @override
  String get dueDate => 'Due Date';

  @override
  String get amountBorrowedDue => 'Amount Borrowed (Due)';

  @override
  String get finalizeAndSaveBill => 'FINALIZE & SAVE BILL';

  @override
  String get saving => 'Saving...';

  @override
  String get billSaved => 'Bill saved';

  @override
  String get printBill => 'Print Bill';

  @override
  String get sharePdf => 'Share PDF';

  @override
  String get done => 'Done';

  @override
  String get productDetails => 'Product Details & Pricing';

  @override
  String get sellingPrice => 'Selling price (₹)';

  @override
  String get mrp => 'MRP (₹)';

  @override
  String get availableStock => 'Available stock';

  @override
  String get makeDefaultPrice => 'Make default for this product';

  @override
  String get savePrices => 'Save prices';

  @override
  String get cartItems => 'Cart Items';

  @override
  String get billSummary => 'Bill Summary';

  @override
  String get due => 'Due';

  @override
  String get advance => 'Advance';

  @override
  String get limit => 'Limit';

  @override
  String get inStock => 'In Stock';

  @override
  String get unit => 'Unit';

  @override
  String get hsn => 'HSN';

  @override
  String get salesManagement => 'Sales Management & Invoicing';

  @override
  String get salesHistoryAndSearch => 'Sales Invoices & History';

  @override
  String get newSale => 'New Sale';

  @override
  String get createInvoice => 'Create New Invoice';

  @override
  String get salesInvoices => 'Sales Invoices';

  @override
  String get allBills => 'All Bills';

  @override
  String get paidStatus => 'Paid';

  @override
  String get borrowPending => 'Borrow / Pending';

  @override
  String get refundReturn => 'Refund / Return';

  @override
  String get billSearch => 'Bill Search';

  @override
  String get billId => 'Bill ID';

  @override
  String get customerNamePrefix => 'Customer Name';

  @override
  String get phone => 'Phone';

  @override
  String get dateRange => 'Date Range';

  @override
  String get clearFilters => 'Clear Filters';

  @override
  String get search => 'Search';

  @override
  String get viewDetail => 'View Detail';

  @override
  String get editBill => 'Edit Bill';

  @override
  String get paySettle => 'Pay / Settle';

  @override
  String get deleteBill => 'Delete Bill';

  @override
  String get upiQr => 'UPI QR';

  @override
  String get customerAndInvoice => 'Customer & Invoice';

  @override
  String get saleItems => 'Sale Items';

  @override
  String get addProductVariant => 'Add Product / Variant';

  @override
  String get invoiceSummary => 'Invoice Summary';

  @override
  String get postSale => 'Post & Save Sale';

  @override
  String get postingLocally => 'Posting locally...';

  @override
  String get totalInvoices => 'Total Invoices';

  @override
  String get totalBilled => 'Total Billed';

  @override
  String get totalCollected => 'Total Collected';

  @override
  String get outstandingDue => 'Outstanding Due';

  @override
  String get allocated => 'Allocated';

  @override
  String get required => 'Required';

  @override
  String get remaining => 'Remaining';

  @override
  String get loadVerifiedBatches => 'Load Verified Batches';

  @override
  String get noBillsFound => 'No bills found matching filters.';

  @override
  String get invoiceDate => 'Invoice Date';

  @override
  String get totalUnpaid => 'Total • Unpaid';

  @override
  String get refreshLocalData => 'Refresh local data';

  @override
  String get removeLine => 'Remove line';

  @override
  String get cancel => 'Cancel';

  @override
  String get addLine => 'Add line';

  @override
  String get loadingBatches => 'Loading local batches...';

  @override
  String get allocateBaseQty => 'Allocate base qty';

  @override
  String get batchAllocations => 'Batch Allocations';

  @override
  String get repaymentDate => 'Repayment Date';

  @override
  String get repaymentTimeline => 'Repayment Timeline';

  @override
  String get allPending => 'All Pending';

  @override
  String get overdue => 'Overdue';

  @override
  String get dueToday => 'Due Today';

  @override
  String get upcomingDue => 'Upcoming Due';

  @override
  String get noRepaymentDate => 'No Due Date';

  @override
  String get setRepaymentDate => 'Set Due Date';

  @override
  String get changeRepaymentDate => 'Change Due Date';

  @override
  String get nextRepaymentDate => 'Next Repayment Due Date';

  @override
  String get repaymentDateUpdated => 'Repayment date updated successfully';

  @override
  String get daysOverdueSuffix => 'days overdue';

  @override
  String get daysRemainingSuffix => 'days left';

  @override
  String get newPurchase => 'New Purchase';

  @override
  String get editDraftPurchase => 'Edit Draft Purchase';

  @override
  String get saveDraft => 'Save Draft';

  @override
  String get reviewAndPost => 'Review & Post';

  @override
  String get supplierBill => 'Supplier Bill';

  @override
  String get scanBill => 'Scan Bill';

  @override
  String get uploadImage => 'Upload Image';

  @override
  String get uploadPdf => 'Upload PDF';

  @override
  String get purchaseItems => 'Purchase Items';

  @override
  String get copyRow => 'Copy Row';

  @override
  String get pasteFromExcel => 'Paste from Excel';

  @override
  String get addRow => 'Add Row';

  @override
  String get filterBySupplier => 'Filter by supplier';

  @override
  String get allSuppliers => 'All Suppliers';

  @override
  String get purchaseDateRange => 'Purchase Date Range';

  @override
  String get searchPurchases =>
      'Search purchase #, supplier invoice, product...';

  @override
  String get totalPaid => 'Total Paid';

  @override
  String get partiallyPaid => 'Partially Paid';

  @override
  String get supplierInvoiceNo => 'Supplier Invoice #';

  @override
  String get purchaseDate => 'Purchase Date';

  @override
  String get purchaseSummary => 'Purchase Summary';

  @override
  String get discountAndCharges => 'Discount & Charges';

  @override
  String get fixedAmount => 'Fixed Amount';

  @override
  String get percentage => 'Percentage';

  @override
  String get recordPayment => 'Record Payment';

  @override
  String get approveAndReceive => 'Approve & Receive';

  @override
  String get approved => 'Approved';

  @override
  String get draft => 'Draft';

  @override
  String get cancelled => 'Cancelled';

  @override
  String get noPurchasesFound => 'No purchases found matching criteria.';

  @override
  String get productNameCol => 'Product';

  @override
  String get variantCol => 'Variant / Spec';

  @override
  String get hsnCol => 'HSN';

  @override
  String get barcodeCol => 'Barcode';

  @override
  String get batchCol => 'Batch No';

  @override
  String get lotCol => 'Supplier Lot';

  @override
  String get mfgDateCol => 'Mfg Date';

  @override
  String get expDateCol => 'Expiry Date';

  @override
  String get qtyCol => 'Qty';

  @override
  String get unitCol => 'Unit';

  @override
  String get purchasePriceCol => 'Rate (₹)';

  @override
  String get gstCol => 'GST %';

  @override
  String get taxableCol => 'Taxable (₹)';

  @override
  String get mrpCol => 'MRP (₹)';

  @override
  String get sellingPriceCol => 'Selling (₹)';

  @override
  String get storeLocationCol => 'Store Location';

  @override
  String get excelSpreadsheetMode => 'Excel Grid Mode';

  @override
  String get inventoryDashboardTitle => 'Inventory Intelligence & Operations';

  @override
  String get inventoryDashboardSubtitle =>
      'Real-time stock monitoring, valuations, reorder alerts & movement management';

  @override
  String get totalItems => 'Total Products / SKUs';

  @override
  String get inStockItems => 'Optimal Stock';

  @override
  String get lowStockAlertCount => 'Low Stock Alerts';

  @override
  String get estimatedInventoryValue => 'Estimated Stock Value';

  @override
  String get reorderRequired => 'Action Required';

  @override
  String get healthyCatalogRatio => 'Healthy stock ratio';

  @override
  String get searchInventoryPlaceholder =>
      'Search by product name, SKU, barcode...';

  @override
  String get filterAll => 'All';

  @override
  String get filterInStock => 'In Stock';

  @override
  String get filterLowStock => 'Low Stock';

  @override
  String get filterOutOfStock => 'Out of Stock';

  @override
  String get filterInactive => 'Inactive';

  @override
  String get sortBy => 'Sort by';

  @override
  String get sortNameAsc => 'Name (A to Z)';

  @override
  String get sortNameDesc => 'Name (Z to A)';

  @override
  String get sortStockAsc => 'Stock (Low to High)';

  @override
  String get sortStockDesc => 'Stock (High to Low)';

  @override
  String get sortPriceDesc => 'Price (High to Low)';

  @override
  String get sortRecentlyUpdated => 'Recently Updated';

  @override
  String get viewModeTable => 'Table View';

  @override
  String get viewModeCards => 'Card View';

  @override
  String get recentlyUpdated => 'Recently updated';

  @override
  String get last30Days => 'Last 30 days';

  @override
  String get allTime => 'All Time';

  @override
  String get importCsv => 'Import CSV';

  @override
  String get exportCsv => 'Export CSV';

  @override
  String get addNewItem => 'Add New Product';

  @override
  String get stockMovement => 'Stock Action';

  @override
  String get stockMovementReceive => 'Receive Purchase Stock (Inward)';

  @override
  String get stockMovementAdjustIn => 'Adjust Stock In (Found / Return)';

  @override
  String get stockMovementAdjustOut => 'Adjust Stock Out (Transfer / Sample)';

  @override
  String get stockMovementDamageLoss => 'Damage / Breakage / Expiry Loss';

  @override
  String get stockMovementCountCorrection => 'Physical Stock Count Correction';

  @override
  String get currentStock => 'Current Available Stock';

  @override
  String get quantityInBaseUnits => 'Quantity to Adjust';

  @override
  String get unitCostRupees => 'Unit Cost (₹)';

  @override
  String get reasonForMovement => 'Audit Reason / Reference';

  @override
  String get reasonHint =>
      'e.g., Physical count audit, vendor return, transit damage';

  @override
  String get newStockPreview => 'New Stock after Adjustment';

  @override
  String get quickAdjust => 'Quick Adjust';

  @override
  String get stockHistory => 'Stock Info & Spec';

  @override
  String get reorderThreshold => 'Reorder Threshold';

  @override
  String get sellingPriceLabel => 'Selling Price';

  @override
  String get stockValuationLabel => 'Stock Valuation';

  @override
  String get noInventoryItems => 'No inventory items found';

  @override
  String get noInventorySubtitle =>
      'Try adjusting your search keywords or filter status above';

  @override
  String get noAccessInventory =>
      'You do not have permission to access the Inventory module.';

  @override
  String get stockUpdatedSuccess => 'Stock updated successfully.';

  @override
  String get inventoryExportedSuccess => 'Inventory exported successfully.';

  @override
  String get enterQuantityError =>
      'Please enter a valid quantity greater than zero.';

  @override
  String get stockStatusHealthy => 'Healthy';

  @override
  String get stockStatusLow => 'Low Stock';

  @override
  String get stockStatusOut => 'Out of Stock';

  @override
  String get stockStatusInactive => 'Inactive';

  @override
  String get refreshTooltip => 'Refresh stock data';

  @override
  String get viewSpecs => 'View Details';

  @override
  String get itemDetails => 'Product & Stock Details';

  @override
  String get close => 'Close';

  @override
  String get brand => 'Brand';

  @override
  String get category => 'Category';

  @override
  String get mrpLabel => 'MRP';

  @override
  String get purchaseRateLabel => 'Purchase Rate';

  @override
  String get taxRateLabel => 'Tax Rate';

  @override
  String get apply => 'Apply Action';

  @override
  String get unitsLabel => 'units';

  @override
  String get importPreviewTitle => 'Import CSV Preview';

  @override
  String get barcodeDashboard => 'Barcode Dashboard';

  @override
  String get barcodeSubtitle =>
      'Select eligible variants, preview thermal labels, and print or download.';

  @override
  String get barcodePrinting => 'Barcode Printing';

  @override
  String get barcodeLookup => 'Barcode Lookup';

  @override
  String get totalVariants => 'Total Variants';

  @override
  String get barcodedItems => 'Barcoded';

  @override
  String get missingBarcode => 'Missing Barcode';

  @override
  String get printReady => 'Print Ready';

  @override
  String get findProductByBarcode => 'Find a product by its saved barcode';

  @override
  String get typeOrScanBarcode => 'Type or scan a barcode';

  @override
  String get barcodeNotFound => 'Barcode not found';

  @override
  String get labelTemplate => 'Label Template';

  @override
  String get labelSize => 'Label Size';

  @override
  String get previewSelected => 'Preview Selected';

  @override
  String get downloadPdf => 'Download PDF';

  @override
  String get printLabels => 'Print Labels';

  @override
  String get selectAllVisible => 'Select All Visible';

  @override
  String get clearSelection => 'Clear Selection';

  @override
  String get showIneligible => 'Show ineligible';

  @override
  String get copiesForSelected => 'Copies for selected';

  @override
  String get verifiedStock => 'Verified Stock';

  @override
  String get reportsNavTitle => 'Reports & Analytics';

  @override
  String get oneClickAuditHeroTitle => 'Automated Financial Reconciliation';

  @override
  String get oneClickAuditHeroSubtitle =>
      'Review recorded sales, purchases, inventory, expenses and payroll with source evidence and disclosed limitations.';

  @override
  String get launchCompleteAudit => 'Generate reconciliation';

  @override
  String get downloadAuditPdf => 'Download review PDF';

  @override
  String get downloadAuditExcel => 'Export review Excel';

  @override
  String get auditReportReady => 'Review available';

  @override
  String get auditsAndStatutory => 'Financial review and tax schedules';

  @override
  String get completeAuditTileTitle => 'Financial Reconciliation';

  @override
  String get completeAuditTileSubtitle =>
      'Source evidence, outlet consolidation and unresolved differences';

  @override
  String get financialYearPreset => 'Financial Year';

  @override
  String get statutoryComplianceBadge => 'Evidence-based review';

  @override
  String get turnoverGross => 'Gross Turnover';

  @override
  String get costOfGoodsSold => 'Cost of Goods Sold (COGS)';

  @override
  String get grossProfitLabel => 'Gross Profit';

  @override
  String get operatingExpensesLabel => 'Operating Expenses';

  @override
  String get netProfitLabel => 'Net Operating Profit (NPBT)';

  @override
  String get workingCapitalLabel => 'Net Working Capital';

  @override
  String get languageSelector => 'Language';

  @override
  String get english => 'English';

  @override
  String get hindi => 'हिंदी (Hindi)';

  @override
  String get bengali => 'বাংলা (Bengali)';

  @override
  String get selectLanguage => 'Select Language';

  @override
  String get salesAndCollections => 'Sales and collections';

  @override
  String get purchasesAndInventory => 'Purchases and inventory';

  @override
  String get taxAndProfit => 'Tax and profit';

  @override
  String get productDashboardTitle => 'Products & Catalogue';

  @override
  String get productDashboardSubtitle =>
      'Centralized catalogue, multi-variant specifications, pricing & outlet allocation';

  @override
  String get addProduct => 'Add Product';

  @override
  String get addExistingToOutlet => 'Add Existing to Outlet';

  @override
  String get totalProducts => 'Total Products';

  @override
  String get activeProducts => 'Active Products';

  @override
  String get inactiveProducts => 'Inactive Products';

  @override
  String get stockAlerts => 'Stock Alerts';

  @override
  String get searchProductPlaceholder =>
      'Search product, brand, SKU, barcode, or category...';

  @override
  String get filterMultiVariant => 'Multi-Variant';

  @override
  String get allBrands => 'All Brands';

  @override
  String get allCategories => 'All Categories';

  @override
  String get allSubcategories => 'All Subcategories';

  @override
  String get allStatuses => 'All Statuses';

  @override
  String get statusActive => 'Active';

  @override
  String get statusInactive => 'Inactive';

  @override
  String get syncStatus => 'Sync Status';

  @override
  String get syncSynced => 'Synced';

  @override
  String get syncSyncing => 'Syncing';

  @override
  String get syncPending => 'Pending';

  @override
  String get syncError => 'Sync Error';

  @override
  String get actions => 'Actions';

  @override
  String get viewProduct => 'View Details';

  @override
  String get editProduct => 'Edit Product / Manage Variants';

  @override
  String get duplicateProduct => 'Duplicate';

  @override
  String get manageOutletAssignment => 'Manage outlet assignment';

  @override
  String get removeFromThisOutlet => 'Remove from this outlet';

  @override
  String get activateInThisOutlet => 'Activate in this outlet';

  @override
  String get deleteProduct => 'Delete';

  @override
  String get printBarcode => 'Print Barcode';

  @override
  String get editVariant => 'Edit Variant';

  @override
  String get noProductsFound => 'No products match your search.';

  @override
  String get noProductsOutletSubtitle =>
      'No Products are assigned to this outlet. Add a new Product.';

  @override
  String get noProductsFoundSubtitle =>
      'Try adjusting your search keywords or filter status.';

  @override
  String get deleteProductsConfirmTitle => 'Delete products?';

  @override
  String get deleteProductsConfirmMessage =>
      'Products will be archived. Historical transactions and variants will be preserved.';

  @override
  String get changeStatusConfirmTitle => 'Change product status?';

  @override
  String get businessDashboardTitle => 'Business & Organization Workspace';

  @override
  String get businessDashboardSubtitle =>
      'Choose a business to continue. Your businesses stay separate.';

  @override
  String get selectBusiness => 'Select a business';

  @override
  String get addBusiness => 'Add business';

  @override
  String get totalBusinesses => 'Total Businesses';

  @override
  String get activeBusinesses => 'Active Businesses';

  @override
  String get searchBusinessesPlaceholder =>
      'Search by business name, GSTIN, type, or address...';

  @override
  String get noBusinessesFound => 'No businesses found';

  @override
  String get noBusinessesFoundSubtitle =>
      'There are no active businesses available for this account.';

  @override
  String get openWorkspace => 'Open Workspace';

  @override
  String get enterStore => 'Enter Store';

  @override
  String get outletDashboardTitle => 'Outlet & Store Workspace';

  @override
  String get outletDashboardSubtitle =>
      'Choose an outlet to continue store billing, stock & inventory operations.';

  @override
  String get selectOutlet => 'Select an outlet';

  @override
  String get addOutlet => 'Add outlet';

  @override
  String get searchOutletsPlaceholder =>
      'Search by outlet name, code, type, or address...';

  @override
  String get noOutletsFound => 'No Outlet Available';

  @override
  String get noOutletsFoundSubtitle =>
      'This Business has no active Outlets yet. Add an Outlet to continue.';

  @override
  String get createBusinessTitle => 'Create your business';

  @override
  String get createBusinessSubtitle =>
      'Add the business profile. You can create more businesses later.';

  @override
  String get createOutletTitle => 'Add Outlet';

  @override
  String get createOutletSubtitle =>
      'This outlet belongs to the selected business.';

  @override
  String get businessNameLabel => 'Business Name *';

  @override
  String get businessEmailLabel => 'Business Email *';

  @override
  String get businessPhoneLabel => 'Business Contact Number *';

  @override
  String get businessAddressLabel => 'Business Address *';

  @override
  String get outletNameLabel => 'Outlet Name *';

  @override
  String get outletAddressLabel => 'Outlet Address *';

  @override
  String get outletContactNumberLabel => 'Contact Number *';

  @override
  String get outletCodeNotice => 'Outlet Code: Auto-generated when saved';

  @override
  String get gstinOptionalLabel => 'GSTIN (optional)';

  @override
  String get saveBusiness => 'Create Business';

  @override
  String get saveOutlet => 'Save Outlet';

  @override
  String get discardChangesTitle => 'Discard Changes?';

  @override
  String get discardChangesSubtitle => 'Your entered information will be lost.';

  @override
  String get discard => 'Discard';

  @override
  String get expensesDashboardTitle => 'Expenses & Outflows';

  @override
  String get expensesDashboardSubtitle =>
      'Track operational overheads, store upkeep, utilities, salaries, and petty cash';

  @override
  String get customDateRange => 'Custom range';

  @override
  String get sortDateNewest => 'Date: Newest';

  @override
  String get sortDateOldest => 'Date: Oldest';

  @override
  String get sortAmountHighLow => 'Amount: High to low';

  @override
  String get sortAmountLowHigh => 'Amount: Low to high';

  @override
  String get sortTitleAz => 'Title: A to Z';

  @override
  String get filtered => 'Filtered';

  @override
  String get recordExpense => 'Record Expense';

  @override
  String get newExpenseVoucher => 'New Expense Voucher';

  @override
  String get todayExpenses => 'Today\'s Expense';

  @override
  String get thisMonthExpenses => 'This Month\'s Total';

  @override
  String get cashOutflow => 'Cash Outflow';

  @override
  String get digitalOutflow => 'Digital & Bank';

  @override
  String get activeVouchers => 'Active Records';

  @override
  String get activeDisbursementsToday => 'Disbursements today';

  @override
  String get currentBillingPeriod => 'Current billing period';

  @override
  String get disbursedFromTill => 'From cash till';

  @override
  String get digitalAndBankSubtitle => 'UPI, Bank, Card & Cheque';

  @override
  String get totalExpenseVouchers => 'Total expense vouchers';

  @override
  String get searchExpensesPlaceholder =>
      'Search by title, payee, voucher #, notes...';

  @override
  String get periodFilter => 'Period';

  @override
  String get filterPeriodToday => 'Today';

  @override
  String get filterPeriodThisWeek => 'This Week';

  @override
  String get filterPeriodThisMonth => 'This Month';

  @override
  String get filterPeriodThisQuarter => 'This Quarter';

  @override
  String get filterPeriodAllTime => 'All Time';

  @override
  String get categoryFilter => 'Category';

  @override
  String get paymentModeFilter => 'Payment Mode';

  @override
  String get allPaymentModes => 'All Modes';

  @override
  String get paymentModeCash => 'Cash';

  @override
  String get paymentModeUpi => 'UPI';

  @override
  String get paymentModeBankTransfer => 'Bank Transfer';

  @override
  String get paymentModeCheque => 'Cheque';

  @override
  String get paymentModeCard => 'Card';

  @override
  String get statusFilter => 'Status';

  @override
  String get statusAll => 'All Status';

  @override
  String get statusVoided => 'Voided';

  @override
  String get dateTime => 'Date & Time';

  @override
  String get titleOrDescription => 'Title / Description';

  @override
  String get payee => 'Payee / Paid To';

  @override
  String get refVoucherNumber => 'Ref / Voucher #';

  @override
  String get amountRupees => 'Amount';

  @override
  String get voidExpense => 'Void Expense';

  @override
  String get voidExpenseConfirmTitle => 'Void Expense Voucher?';

  @override
  String get voidExpenseConfirmMessage =>
      'Are you sure you want to void this expense? This action will mark it as VOIDED and exclude it from active totals.';

  @override
  String get expenseVoidedSuccess => 'Expense voucher voided successfully.';

  @override
  String get expenseSavedSuccess => 'Expense voucher recorded successfully.';

  @override
  String get spendingByCategory => 'Spending by Category';

  @override
  String get noExpensesFound => 'No expense records found';

  @override
  String get noExpensesSubtitle =>
      'Record operational overheads, utilities, or petty cash to start tracking';

  @override
  String get noExpensesMatchingFilters =>
      'No expense vouchers match your active filters.';

  @override
  String get clearAllFilters => 'Clear Filters';

  @override
  String get expenseDetails => 'Expense Voucher Details';

  @override
  String get auditInfo => 'Audit Information';

  @override
  String get voucherDetails => 'Voucher Details';

  @override
  String get saveExpense => 'Save Expense';

  @override
  String get amountRequiredError =>
      'Amount is required and must be greater than zero.';

  @override
  String get descriptionRequiredError => 'Description / Title is required.';

  @override
  String get quickAddAmount => 'Quick Amount';

  @override
  String get suggestions => 'Suggestions';

  @override
  String get printVoucher => 'Print Voucher';

  @override
  String get expenseDate => 'Expense Date';

  @override
  String get remarksOrNotes => 'Remarks / Notes';

  @override
  String get createdBy => 'Created By';

  @override
  String get customerDashboard => 'Customer Hub';

  @override
  String get customerDashboardSubtitle =>
      'Manage customer profiles, credit limits, outstanding receivables, and instant UPI collection.';

  @override
  String get totalCustomers => 'Total Customers';

  @override
  String get totalDueReceivable => 'Total Due Receivable';

  @override
  String get totalAdvanceReceived => 'Total Advance Received';

  @override
  String get creditExtended => 'Credit Extended';

  @override
  String get registeredAccounts => 'Registered accounts';

  @override
  String get accountsWithDue => 'Accounts with due';

  @override
  String get accountsWithAdvance => 'Accounts with advance';

  @override
  String get activeCreditLines => 'Active credit lines';

  @override
  String get sortCustomers => 'Sort customers';

  @override
  String get sortSuppliers => 'Sort suppliers';

  @override
  String get dueHighToLow => 'Due: High to low';

  @override
  String get advanceHighToLow => 'Advance: High to low';

  @override
  String get nameAToZ => 'Name: A to Z';

  @override
  String get nameZToA => 'Name: Z to A';

  @override
  String get linkedToBusiness => 'Linked to business';

  @override
  String get readyForPurchases => 'Ready for purchases';

  @override
  String get deactivatedAccounts => 'Deactivated accounts';

  @override
  String get availableToLink => 'Available to link';

  @override
  String get fromOtherBusinesses => 'From other businesses';

  @override
  String get allCustomers => 'All Customers';

  @override
  String get hasDue => 'Has Due';

  @override
  String get hasAdvance => 'Has Advance';

  @override
  String get settled => 'Settled';

  @override
  String get searchCustomers => 'Search customers';

  @override
  String get searchCustomersPlaceholder =>
      'Search by customer name, phone, GSTIN, or city...';

  @override
  String get addCustomer => 'Add Customer';

  @override
  String get editCustomer => 'Edit Customer';

  @override
  String get customerSaved =>
      'Customer saved locally and queued for background sync.';

  @override
  String get customerUpdated => 'Customer details updated successfully.';

  @override
  String get noCustomersFound => 'No customers found';

  @override
  String get noCustomersFoundSubtitle =>
      'No customer profiles match your search criteria.';

  @override
  String get noCustomersYet => 'No customers saved yet';

  @override
  String get noCustomersYetSubtitle =>
      'Add your first customer to track sales, ledger dues, and contact details.';

  @override
  String get showUpiQr => 'Show UPI QR to collect due';

  @override
  String get upiCollect => 'UPI Collect';

  @override
  String get creditLimit => 'Credit Limit';

  @override
  String get openingBalance => 'Opening Balance';

  @override
  String get openingBalanceHelper =>
      'Positive = customer owes you (Due), Negative = advance received';

  @override
  String get currentBalance => 'Current Balance';

  @override
  String get customerName => 'Customer Name';

  @override
  String get stateCode => 'State Code';

  @override
  String get billingAddress => 'Billing Address';

  @override
  String get supplierDashboard => 'Supplier & Vendor Hub';

  @override
  String get supplierDashboardSubtitle =>
      'Oversee procurement partners, trade credit terms, advance balances, and refunds.';

  @override
  String get totalSuppliers => 'Total Suppliers';

  @override
  String get activeSuppliers => 'Active Suppliers';

  @override
  String get inactiveSuppliers => 'Inactive Suppliers';

  @override
  String get totalSupplierAdvance => 'Available Advance';

  @override
  String get preferredSuppliers => 'Preferred Partners';

  @override
  String get addSupplier => 'Add Supplier';

  @override
  String get editSupplier => 'Edit Supplier';

  @override
  String get linkExistingSupplier => 'Link Existing Supplier';

  @override
  String get searchSuppliers => 'Search suppliers';

  @override
  String get searchSuppliersPlaceholder =>
      'Search by supplier name, contact person, mobile, or GSTIN...';

  @override
  String get noSuppliersFound => 'No suppliers found';

  @override
  String get noSuppliersFoundSubtitle =>
      'No supplier profiles match your search criteria.';

  @override
  String get noSuppliersYet => 'No suppliers linked yet';

  @override
  String get noSuppliersYetSubtitle =>
      'No suppliers are linked to this business. Add a supplier or link one from another business.';

  @override
  String get availableAdvance => 'Available Advance';

  @override
  String get recordRefund => 'Record Refund';

  @override
  String get supplierAdvance => 'Supplier Advance';

  @override
  String get businessTerms => 'Business Terms';

  @override
  String get optionalBusinessTerms => 'Optional Business Terms';

  @override
  String get optionalBusinessTermsSubtitle =>
      'Configure commercial terms now, or leave them at zero and update them later.';

  @override
  String get paymentTermsDays => 'Payment Terms (days)';

  @override
  String get openingPayable => 'Opening Payable';

  @override
  String get openingPayableHelper =>
      'Opening payable is recorded in the ledger and cannot be edited here.';

  @override
  String get preferredSupplier => 'Preferred Supplier';

  @override
  String get preferredSupplierSubtitle => 'Used as a supplier indicator only.';

  @override
  String get contactPerson => 'Contact Person';

  @override
  String get supplierMobile => 'Mobile Number';

  @override
  String get supplierEmail => 'Email Address';

  @override
  String get whatsappNumber => 'WhatsApp Number';

  @override
  String get panNumber => 'PAN Number';

  @override
  String get supplierType => 'Supplier Type / Category';

  @override
  String get supplierSaved =>
      'Supplier saved successfully and queued for sync.';

  @override
  String get supplierUpdated => 'Supplier updated successfully.';

  @override
  String get logoutConfirmTitle => 'Log out?';

  @override
  String get logoutConfirmMessage =>
      'Are you sure you want to log out of your account? Any unsaved changes in progress may be lost.';

  @override
  String get aboutAppTitle => 'About NubiBill Business ERP';

  @override
  String get aboutAppSubtitle =>
      'Enterprise Multi-Outlet Retail & Wholesale ERP System';

  @override
  String get companyWebsite => 'Official Website';

  @override
  String get documentation => 'Documentation & User Guide';

  @override
  String get technicalSupport => 'Technical Support';

  @override
  String get privacyPolicy => 'Privacy Policy';

  @override
  String get termsOfService => 'Terms of Service';

  @override
  String get aboutAppDescription =>
      'High-performance, offline-first enterprise management solution engineered for retail, wholesale, godown logistics, and commercial trade operations.';
}
