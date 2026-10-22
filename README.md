# NubiBill ERP

Flutter authentication and workspace entry flow for a multi-business, multi-outlet ERP. Authentication identifies a person; the UID-based profile and membership records determine whether they can access a workspace. Business and outlet selection happens after login.

## Configuration

Pass the Firebase project ID and Web API key at run time. The API key is client configuration; restrict it in Google Cloud/Firebase.

```sh
flutter run -d macos \
  --dart-define=FIREBASE_PROJECT_ID=your-project-id \
  --dart-define=FIREBASE_API_KEY=your-web-api-key \
  --dart-define=APP_VERSION=1.0.0+1
```

Use the same `FIREBASE_PROJECT_ID`, `FIREBASE_API_KEY`, and `APP_VERSION` defines with `flutter run` and `flutter build` on each machine. `EnvironmentConfig.diagnostics()` reports the project ID, whether required settings are present, and the app version without returning the API key. Firebase Authentication REST handles sign-in and token refresh. All Firestore CRUD, queries, aggregation, and atomic writes use the Firestore REST API through `FirestoreRestService`; multi-document changes use `documents:commit` with `exists` or `updateTime` preconditions. No Firebase Flutter Firestore SDK is used.

## Firestore records expected by the app

- `app_config/system`: `isActive` boolean; optional `maintenanceTitle`, `maintenanceMessage`, and `maintenanceImageUrl` strings.
- `user/{FIREBASE_AUTH_UID}`: `uid`, `email`, `name`, `accountType` (`owner` or `employee`), and `isActive` boolean; optional `phone` and `roleId`. The UID document is the primary lookup. Temporary email-document lookup is supported for migration, but a stored `uid` must still match the authenticated UID.
- `business_types/{businessTypeId}`: master-data documents with `name`, `isActive`, and `displayOrder`; optional `description`. Only active records appear in the business form. The document ID is the `businessTypeId`.
- `business_sub_types/{businessSubTypeId}`: master-data documents with `businessTypeId`, `name`, `isActive`, and `displayOrder`; optional `description`. The outlet form loads only active sub-types belonging to the selected business type. The document ID is the sub-type ID.
- `businesses/{businessId}`: generated document ID, matching `businessId`, `ownerUid`, `businessName`, `normalizedBusinessName`, `businessTypeId`, `businessTypeName`, `email`, `phone`, `address`, and `isActive`; optional GST fields. The business type ID references `business_types`. Legacy `businessType` and `status` records remain readable.
- `outlets/{outletId}`: one document per Outlet, with a generated unique internal `outletId`, Business-scoped sequence `outletCode` (for example `OUT-0001`), `tenantId`, shared parent `businessId`, `ownerUid`, `outletName`, `name`, `outletTypeId`, `outletTypeName`, `contactNumber`, `address`, `isActive`, `status`, timestamps, and version; optional GST fields. Multiple Outlet documents may reference the same Business. Sequence state is kept in `document_sequences/{tenantId}_{businessId}_OUTLET`. The outlet type ID references `business_sub_types`, whose `businessTypeId` must match the parent business.
- `godowns/{godownId}`: Business-owned Godowns with immutable `godownCode` (`GD-0001` sequence), `godownScope` (`CENTRAL` or `OUTLET`), nullable Outlet assignment, nested address/contact/capacity maps, and audit metadata. Sequence state is `document_sequences/{tenantId}_{businessId}_GODOWN`; capacity utilization remains unavailable until verified product dimensions and location-based stock are implemented.
- `business_name_reservations/{reservationId}`: create-only uniqueness claims keyed by owner UID and normalized business name. The repository also checks existing business records for a friendly early duplicate message.
- `employees/{employeeId}`: `uid`, `ownerUid`, `name`, `email`, `status`, `businessIds`, and `outletIds`; optional `roleId` and `phone`. The app resolves an employee by UID and verifies their business/outlet assignments.
- `roles/{roleId}`: `roleId`, `roleName`, `permissions`, and `status` (`active` or `inactive`). Employee access uses this record; `accountType` remains separate from `roleId`.
- `invoices`, `purchases`, `products`, and `customers`: dashboard queries expect `businessId` and `outletId` on each operational document. Invoices and purchases include numeric `totalAmount`; invoices also include `invoiceNumber`, `paymentStatus`, `createdAt`, and optional line-item `items`.

Enable Email/Password under Firebase Authentication. Firestore Security Rules must enforce ownership and membership for every read and write. Client-side checks guide navigation but do not replace backend authorization. The signed-in ID token is attached to protected Firestore requests.

The app requires rules that allow owners to read active master data, create businesses only for their authenticated UID, create outlets only for a business they own, and create-only access to their own business-name reservations. Rules must also verify that `businessTypeId` and `outletTypeId` reference active master records and that the outlet sub-type belongs to the parent business type. Firestore rules are not included in this repository, so deploy these policies in the Firebase project before enabling creation. A client-only reservation check cannot stop a custom client from bypassing the application; server rules or a trusted backend must enforce the same uniqueness constraint. A production GST verification provider is not configured; supplied GSTINs are format-checked but creation remains blocked until a provider returns a successful verification result.

## Sign-in and workspace flow

Firebase Authentication REST returns the UID and ID token used for Firestore REST requests. The app loads the `user/{uid}` profile, checks `isActive` and `accountType`, then resolves workspaces:

- Owners load active businesses by `ownerUid`. With none, they can create a business. One business is selected automatically; multiple businesses show a selector. The selected business’s outlets follow the same create, auto-select, or selector flow.
- Employees load their employee record, validate its status and active role, then load only assigned businesses and outlets. Employees with no valid access are denied.
- The selected business and outlet IDs are saved locally and revalidated against fresh backend access on session restoration. Logging out clears authentication and workspace context.

Refresh tokens and selected workspace context use platform secure storage. Remember Me defaults off; when enabled, the REST refresh token is stored and refreshed on startup. ID tokens are memory-only, and passwords are never stored.

## Code boundaries

- `lib/core/constants/firebase_constants.dart` is the source of Firebase REST endpoints and collection names.
- `lib/data/services` contains Firebase REST/HTTP adapters, including REST `:commit` atomic writes with optimistic concurrency preconditions.
- `lib/data/repositories` resolves users, roles, employees, businesses, and outlets.
- `lib/data/repositories/business_type_repository.dart` and `business_sub_type_repository.dart` load the active, ordered dropdown values from Firestore.
- `lib/core/utils/validators.dart` centralizes business name, email, Indian phone, and GSTIN validation/normalization.
- `lib/data/services/gst_verification_service.dart` defines the GST provider boundary; the configured default explicitly reports that verification is unavailable.
- `lib/data/repositories/dashboard_repository.dart` loads outlet-scoped totals and sales summaries using Firestore server-side aggregation queries.
- `lib/core/permissions/permission_catalog.dart` centralizes admin navigation and employee module permission mapping.
- `lib/domain/entities/app_context.dart` represents the backend-independent current authorization/workspace context.
- `lib/presentation` contains login, selectors, create-business/outlet forms, and the responsive admin dashboard.
- `lib/routes/app_router.dart` routes based on centralized controller state.

The admin dashboard displays sales, purchases, active product and customer totals, a seven-day sales chart, recent invoices, and top selling products for the selected outlet. Its sidebar is permission-filtered for employees. Operational module screens such as billing, inventory, employee management, and reports are not connected yet.

The scoped dashboard queries use composite Firestore indexes described in `firestore.indexes.json`. Deploy those indexes to the Firebase project before using the dashboard. Firestore supports server-side count and sum aggregation queries, so the dashboard does not need to download every invoice or product document to calculate its headline totals.
