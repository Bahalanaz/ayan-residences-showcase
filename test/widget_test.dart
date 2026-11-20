import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ayan_residences/main.dart';
import 'package:ayan_residences/admin/admin_state.dart';
import 'package:ayan_residences/admin/screens/contract_admin_screen.dart';
import 'package:ayan_residences/admin/screens/units_screen.dart';
import 'package:ayan_residences/screens/maintenance_screen.dart';
import 'package:ayan_residences/admin/screens/payment_methods_screen.dart';
import 'package:ayan_residences/admin/screens/admin_more_screen.dart';
import 'package:ayan_residences/screens/more_screen.dart';
import 'package:ayan_residences/admin/screens/payments_admin_screen.dart';
import 'package:ayan_residences/admin/screens/complaints_admin_screen.dart';
import 'package:ayan_residences/admin/screens/reports_admin_screen.dart';
import 'package:ayan_residences/widgets/common.dart';
import 'package:ayan_residences/state/app_state.dart';
import 'package:ayan_residences/state/chat_state.dart';
import 'package:ayan_residences/widgets/chat_view.dart';
import 'package:ayan_residences/admin/screens/cheques_screen.dart';
import 'package:ayan_residences/admin/screens/cheque_detail_screen.dart';
import 'package:ayan_residences/admin/screens/unit_detail_screen.dart' show UnitDetailScreen;
import 'package:ayan_residences/admin/screens/finance_screen.dart';
import 'package:ayan_residences/admin/screens/finance_report.dart';
import 'package:ayan_residences/admin/screens/unit_scheduling.dart' show BookingForm, CostsSheet, DamageSheet;
import 'package:ayan_residences/screens/cheque_upload_screen.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    // Skip the demo ghost-loading delay so tests see content straight away.
    demoLoadDelay = Duration.zero;
    animateUi = false;
  });

  testWidgets('login, unread popup, then navigate the app', (tester) async {
    // The test font is much wider than Roboto, so use a roomy surface.
    tester.view.physicalSize = const Size(600, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const AyanApp());
    // The app opens on the welcome state.
    expect(find.text('Get started!'), findsOneWidget);
    await tester.tap(find.text('Login'));
    await tester.pumpAndSettle();
    expect(find.text('Welcome!'), findsOneWidget);

    // Tapping the header background goes back to the welcome state.
    await tester.tapAt(const Offset(40, 150));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Login'));
    await tester.pumpAndSettle();

    // Wrong password shows an error.
    await tester.enterText(find.byType(TextFormField).at(0), '123');
    await tester.enterText(find.byType(TextFormField).at(1), 'wrong');
    await tester.tap(find.text('Log In'));
    await tester.pump(const Duration(seconds: 1));
    expect(find.textContaining('Incorrect username'), findsOneWidget);

    await tester.enterText(find.byType(TextFormField).at(1), '123');
    await tester.tap(find.text('Log In'));
    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(seconds: 1));

    // Latest unread notice pops up; the button is locked for 3 seconds.
    expect(find.text('NEW NOTICE'), findsOneWidget);
    expect(find.textContaining('Please read'), findsOneWidget);
    await tester.tap(find.textContaining('Please read'));
    await tester.pump();
    expect(appState.notices.first.acknowledged, isFalse);

    await tester.pump(const Duration(seconds: 3));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Mark as read'), findsOneWidget);
    await tester.tap(find.text('Mark as read'));
    await tester.pumpAndSettle(const Duration(seconds: 3));
    expect(appState.notices.first.acknowledged, isTrue);
    expect(find.text('NEW NOTICE'), findsNothing);

    expect(find.text('Hello, Juan!'), findsOneWidget);
    // The Monthly Rent card opens the payment history.
    await tester.tap(find.text('Monthly Rent'));
    await tester.pumpAndSettle();
    expect(find.text('Payment History'), findsOneWidget);
    expect(find.text('Transaction History'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();

    // Pay Rent opens the three payment tabs.
    await tester.tap(find.text('Pay Rent'));
    await tester.pumpAndSettle();
    expect(find.text('Pay Now'), findsOneWidget);
    expect(find.text('Pay with'), findsOneWidget);
    expect(find.text('Amount due'), findsOneWidget);
    // Where to send money yourself.
    await tester.tap(find.text('Payment Details'));
    await tester.pumpAndSettle();
    expect(find.text('Send to'), findsOneWidget);
    expect(find.text('Account details'), findsOneWidget);
    // Which month, then the receipt.
    await tester.tap(find.text('Payment Proof'));
    await tester.pumpAndSettle();
    expect(find.text('Which month are you paying for?'), findsOneWidget);
    expect(find.text('October 2026'), findsWidgets);
    // Paying through November means October + November: ₱16,000 in total,
    // and the stay is paid until Nov 30.
    await tester.tap(find.text('November 2026'));
    await tester.pumpAndSettle();
    expect(find.text('₱16,000.00'), findsOneWidget);
    expect(find.textContaining('paid until Nov 30, 2026'), findsOneWidget);
    expect(find.text('Your proof'), findsOneWidget);
    await tester.tap(find.text('Pay Now'));
    await tester.pumpAndSettle();

    // Pay online: QR Ph is preselected; checkout, confirm, success.
    final payBtn = find.widgetWithText(GoldButton, 'Pay ₱8,112.00');
    await tester.ensureVisible(payBtn);
    await tester.tap(payBtn);
    await tester.pumpAndSettle();
    expect(find.text('Secure checkout'), findsOneWidget);
    await tester.tap(find.text("I've paid"));
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(find.text('Payment successful'), findsOneWidget);
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    // After paying, the history opens.
    expect(find.text('Transaction History'), findsOneWidget);
    expect(appState.currentRentPaid, isTrue);
    // October is paid; November's rent (due Nov 5) is already listed.
    expect(adminState.unpaidFor('Juan Dela Cruz').map((c) => c.title), ['November 2026 rent']);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(find.text('Calendar'));
    await tester.pumpAndSettle();
    expect(find.text('Repairs, maintenance and due dates'), findsOneWidget);
    await tester.tap(find.text('Whole month'));
    await tester.pumpAndSettle();
    expect(find.text('THURSDAY, OCT 29'), findsOneWidget);

    // Chat opens from the Contact Management card on Home.
    await tester.tap(find.text('Home'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Contact Management'));
    await tester.tap(find.text('Contact Management'));
    await tester.pumpAndSettle();
    expect(find.text('Management · private chat'), findsOneWidget);
    expect(find.textContaining('Slot B-12'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Thanks! See https://example.com/map.');
    await tester.tap(find.byIcon(Icons.send_rounded));
    await tester.pumpAndSettle();
    expect(chatState.messages('Juan Dela Cruz').last.text, 'Thanks! See https://example.com/map.');
    // The bottom bar is hidden inside the chat; back returns to the tabs.
    expect(find.text('Notices'), findsNothing);
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(find.text('Notices'));
    await tester.pumpAndSettle();
    expect(find.text('Announcements & Rules'), findsOneWidget);

    await tester.tap(find.text('Account'));
    await tester.pumpAndSettle();
    expect(find.text('Tenant Account & Records'), findsOneWidget);
  });

  testWidgets('tenant signs a document and admin accepts it', (tester) async {
    tester.view.physicalSize = const Size(600, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    chatState.requestSignature('Grace Santos', 'Lease agreement');
    final msg = chatState.messages('Grace Santos').last;
    expect(msg.sign, SignStatus.awaiting);

    await tester.pumpWidget(MaterialApp(home: SignScreen(msg, tenant: 'Grace Santos')));
    await tester.pumpAndSettle();
    // Tap Sign, draw a stroke on the pad, Done, tick the box, submit.
    await tester.tap(find.widgetWithText(GoldButton, 'Sign'));
    await tester.pumpAndSettle();
    final pad = find.text('Sign here');
    final gesture = await tester.startGesture(tester.getCenter(pad));
    await gesture.moveBy(const Offset(60, 20));
    await gesture.moveBy(const Offset(40, -30));
    await gesture.up();
    await tester.pump();
    await tester.tap(find.text('Done'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Checkbox));
    await tester.pump();
    await tester.tap(find.text('Submit signed document'));
    await tester.pumpAndSettle();
    // Only the account owner can sign: a wrong password is refused.
    await tester.enterText(find.byType(TextField).last, 'wrong');
    await tester.tap(find.widgetWithText(FilledButton, 'Sign'));
    await tester.pumpAndSettle();
    expect(find.text('Wrong password'), findsOneWidget);
    await tester.enterText(find.byType(TextField).last, 'ayan2468');
    await tester.tap(find.widgetWithText(FilledButton, 'Sign'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await tester.pumpAndSettle();
    expect(msg.sign, SignStatus.signed);
    expect(msg.signature, isNotNull);
    expect(msg.audit?.account, 'grace101');

    chatState.requestAgain('Grace Santos', msg, 'Sign inside the box');
    expect(msg.sign, SignStatus.awaiting);
    expect(msg.revision, 1);
    chatState.complete(msg);
    expect(msg.sign, SignStatus.completed);

    // A tenant's own PDF joins the chat only once it is signed.
    final before = chatState.messages('Grace Santos').length;
    final draft = chatState.draftPdf('House rules ack.pdf', Uint8List(2048));
    expect(draft.docTitle, 'House rules ack');
    expect(chatState.messages('Grace Santos').length, before);
    chatState.sign('Grace Santos', draft, Uint8List(4));
    expect(chatState.messages('Grace Santos').length, before + 1);
    expect(chatState.messages('Grace Santos').last.sign, SignStatus.signed);
  });

  test('admin records an outside payment and the month is cleared', () {
    final paolo = adminState.tenants.firstWhere((t) => t.name == 'Juan Dela Cruz');
    final charge = adminState.unpaidFor(paolo.name).first;
    expect(charge.paid, isFalse);
    final until = paolo.paidUntil;
    final before = adminState.payments.length;

    adminState.recordPayment(paolo,
        charge: charge,
        amount: charge.amount,
        method: 'GCash',
        reference: '5521 8890',
        date: 'Oct 28, 2026');

    expect(charge.paid, isTrue);
    expect(charge.overdue, isFalse);
    expect(adminState.payments.length, before + 1);
    final p = adminState.payments.first;
    expect(p.status, PayStatus.verified);
    expect(p.recordedByAdmin, isTrue);
    expect(paolo.paidUntil!.isAfter(until!), isTrue);
    // The tenant is told it was received.
    expect(adminState.notices.first.title, 'Payment received');

    // A part payment leaves the charge open.
    final next = ChargeRec(tenant: paolo.name, title: 'November rent', amount: 24000, due: 'Nov 15, 2026');
    adminState.charges.add(next);
    adminState.recordPayment(paolo,
        charge: next, amount: 10000, method: 'Cash', reference: '', date: 'Oct 29, 2026');
    expect(next.paid, isFalse);

    // Clean up so other tests see the usual demo data.
    adminState.charges.remove(next);
    adminState.notices.removeWhere((n) => n.title == 'Payment received');
    appState.allNotices.removeWhere((n) => n.title == 'Payment received');
  });

  test('admin assigns a contract PDF to one tenant', () {
    final juan = adminState.tenants.firstWhere((t) => t.name == 'Juan Dela Cruz');
    expect(juan.contractName, isNull);
    adminState.assignContract(juan, 'Lease Unit 402.pdf', Uint8List(4096));
    expect(juan.contractName, 'Lease Unit 402.pdf');
    expect(juan.contractPdf!.length, 4096);
    expect(appState.allNotices.first.title, 'Your contract is ready');
    expect(appState.allNotices.first.to, 'Juan Dela Cruz');
    adminState.removeContract(juan);
    expect(juan.contractName, isNull);
    adminState.notices.removeWhere((n) => n.title == 'Your contract is ready');
    appState.allNotices.removeWhere((n) => n.title == 'Your contract is ready');
  });

  testWidgets('admin edits the lease terms and the tenant sees them', (tester) async {
    tester.view.physicalSize = const Size(600, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final juan = adminState.tenants.firstWhere((t) => t.name == 'Juan Dela Cruz');
    final before = (juan.rent, juan.deposit, juan.dueDay, juan.leaseEnd);
    await tester.pumpWidget(MaterialApp(home: ContractAdminScreen(juan)));
    expect(find.text('Contract & lease'), findsOneWidget);
    expect(find.text('Lease term: 12 months'), findsOneWidget);
    expect(find.text('Assign contract (PDF)'), findsOneWidget);

    // Nothing to save until something changes.
    expect(tester.widget<GoldButton>(find.widgetWithText(GoldButton, 'Save changes')).onPressed,
        isNull);
    await tester.enterText(find.byType(TextFormField).at(0), '9000');
    await tester.pump();
    await tester.tap(find.widgetWithText(GoldButton, 'Save changes'));
    // Let the button's press animation finish.
    await tester.pump(const Duration(milliseconds: 300));
    expect(juan.rent, 9000);

    // Lease term follows the dates.
    adminState.updateLease(juan,
        start: DateTime(2026, 1, 1),
        end: DateTime(2027, 6, 30),
        rent: 9000,
        dueDay: 15,
        deposit: 9000);
    expect(juan.termMonths, 18);
    expect(juan.dueDay, 15);
    expect(juan.leaseEnd, 'Jun 30, 2027');

    // Put the demo data back for the other tests.
    adminState.updateLease(juan,
        start: DateTime(2026, 1, 1),
        end: parseDate(before.$4)!,
        rent: before.$1,
        dueDay: before.$3,
        deposit: before.$2);
  });

  test('a tenant complaint and damage report reach management', () {
    appState.currentTenant = 'Juan Dela Cruz';
    final before = adminState.complaints.length;
    adminState.fileComplaint('Juan Dela Cruz', 'Noise', 'Loud music after 10 PM');
    expect(adminState.complaints.length, before + 1);
    final c = adminState.complaints.first;
    expect(c.tenant, 'Juan Dela Cruz');
    expect(c.unit, 'Unit 402');
    expect(c.status, ComplaintStatus.open);
    adminState.complaints.remove(c);

    // A report filed in the tenant app shows up in the admin's list.
    final reports = adminState.reports.length;
    appState.addTicket(issue: 'Broken window latch', description: 'Will not close', attachments: 1);
    expect(adminState.reports.length, reports + 1);
    final r = adminState.reports.first;
    expect(r.issue, 'Broken window latch');
    expect(r.tenant, 'Juan Dela Cruz');

    // The tenant adds a photo; management posts an update.
    adminState.addReportPhotos(r.id, 2);
    expect(r.attachments, 3);
    adminState.postReportUpdate(r, 'Carpenter coming Friday');
    expect(r.updates.first.text, 'Carpenter coming Friday');

    adminState.reports.remove(r);
    appState.tickets.removeWhere((t) => t.id == r.id);
  });

  testWidgets('unit page opens only that unit\'s reports and complaints', (tester) async {
    tester.view.physicalSize = const Size(600, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    // Unit 402 is Juan's; Unit 101 has other reports and complaints.
    await tester.pumpWidget(const MaterialApp(home: ReportVerificationScreen(unit: 'Unit 402')));
    expect(find.text('Reports · Unit 402'), findsOneWidget);
    expect(find.text('Bathroom sink faucet leaking'), findsOneWidget);
    expect(find.text('Cracked window glass'), findsNothing);
    expect(find.text('MAINTENANCE'), findsWidgets);

    // Filter by type: damage hides the maintenance report.
    await tester.tap(find.text('Damage'));
    await tester.pumpAndSettle();
    expect(find.text('Bathroom sink faucet leaking'), findsNothing);

    await tester.pumpWidget(const MaterialApp(home: ComplaintsAdminScreen(unit: 'Unit 101')));
    await tester.pumpAndSettle();
    expect(find.text('Complaints · Unit 101'), findsOneWidget);
    await tester.tap(find.text('In progress'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Housekeeping'), findsNothing);
    expect(find.text('Cleanliness'), findsOneWidget);
  });

  testWidgets('Add charge takes a custom type and a picked due date', (tester) async {
    tester.view.physicalSize = const Size(600, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: PaymentsAdminScreen())));
    await tester.tap(find.text('Charges'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add charge').first);
    await tester.pumpAndSettle();

    // The type is a dropdown the admin can add options to; the due date a picker.
    expect(adminState.chargeTypes, ['Maintenance', 'Repairs', 'Utilities', 'Misc']);
    await tester.tap(find.text('Maintenance'));
    await tester.pumpAndSettle();
    expect(find.text('Repairs'), findsOneWidget);
    await tester.tap(find.text('Add a new option'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'Parking slot');
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    expect(adminState.chargeTypes.last, 'Parking slot');
    expect(find.text('Parking slot'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField).at(0), '1500');
    expect(find.text('Nov 5, 2026'), findsOneWidget);
    await tester.tap(find.text('Nov 5, 2026'));
    await tester.pumpAndSettle();
    expect(find.byType(DatePickerDialog), findsOneWidget);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    final before = adminState.charges.length;
    await tester.tap(find.widgetWithText(GoldButton, 'Add charge').last);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(adminState.charges.length, before + 1);
    final c = adminState.charges.first;
    expect(c.title, 'Parking slot');
    expect(c.due, 'Nov 5, 2026');
    adminState.charges.remove(c);
    adminState.chargeTypes.remove('Parking slot');
  });

  testWidgets('admin More tab: settings, help, legal and password change', (tester) async {
    tester.view.physicalSize = const Size(600, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: AdminMoreScreen())));
    expect(find.text('Change password'), findsOneWidget);
    // Help & FAQ was removed.
    expect(find.text('Help & FAQ'), findsNothing);
    expect(find.text('Privacy policy'), findsOneWidget);
    expect(find.text('Terms of use'), findsOneWidget);
    expect(find.textContaining('version 1.0.0'), findsOneWidget);
    // Payment methods moved to the Payments tab.
    expect(find.text('Payment methods'), findsNothing);

    // A wrong current password is refused; the right one changes it.
    await tester.tap(find.text('Change password'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(0), 'nope');
    await tester.enterText(find.byType(TextFormField).at(1), 'newpass');
    await tester.enterText(find.byType(TextFormField).at(2), 'newpass');
    await tester.tap(find.widgetWithText(GoldButton, 'Update password'));
    await tester.pumpAndSettle();
    expect(find.text('That is not your current password'), findsOneWidget);
    expect(adminPassword, '1234');
    await tester.enterText(find.byType(TextFormField).at(0), '1234');
    await tester.tap(find.widgetWithText(GoldButton, 'Update password'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(adminPassword, 'newpass');
    adminPassword = '1234';

  });

  testWidgets('admin adds a payment method and tenants see it', (tester) async {
    tester.view.physicalSize = const Size(600, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final before = appState.payAccounts.length;
    await tester.pumpWidget(const MaterialApp(home: PaymentMethodsScreen()));
    expect(find.text('BDO Unibank'), findsOneWidget);
    await tester.tap(find.text('Add payment method').last);
    await tester.pumpAndSettle();
    // Type Maya is picked, so the name is Maya; fill the rest.
    await tester.tap(find.text('GCash').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Maya').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(0), 'Ayan Residences Maya');
    await tester.enterText(find.byType(TextFormField).at(1), '0918 111 2222');
    await tester.tap(find.widgetWithText(GoldButton, 'Add payment method').last);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    expect(appState.payAccounts.length, before + 1);
    final added = appState.payAccounts.last;
    expect(added.name, 'Maya');
    expect(added.numberLabel, 'Maya number');
    expect(added.copyText, '09181112222');

    appState.deletePayAccount(added);
    expect(appState.payAccounts.length, before);
  });

  testWidgets('villa upload screen lists cheques needing a photo; admin sees new photos', (tester) async {
    tester.view.physicalSize = const Size(600, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    // Leave the shared demo cheques as they were for the other tests.
    final saved = [
      for (final c in adminState.cheques) (c, c.status, c.photo, c.uploadedOn, c.photoChecked)
    ];
    final paidUntil = adminState.tenants.firstWhere((t) => t.name == 'Paolo Garcia').paidUntil;
    addTearDown(() {
      adminState.cheques
        ..clear()
        ..addAll(saved.map((s) => s.$1
          ..status = s.$2
          ..photo = s.$3
          ..uploadedOn = s.$4
          ..photoChecked = s.$5));
      adminState.tenants.firstWhere((t) => t.name == 'Paolo Garcia').paidUntil = paidUntil;
    });
    appState.currentTenant = 'Paolo Garcia';
    await tester.pumpWidget(const MaterialApp(home: ChequeUploadScreen()));
    await tester.pumpAndSettle();
    expect(find.text('Which cheque is this?'), findsOneWidget);
    expect(find.text('Another cheque'), findsOneWidget);
    expect(find.text('Take or choose a photo'), findsOneWidget);
    // Nothing to send until a photo is chosen.
    final send = tester.widget<GoldButton>(find.widgetWithText(GoldButton, 'Send cheque photo'));
    expect(send.onPressed, isNull);

    final before = adminState.chequesWithNewPhotos.length;
    final c = adminState.uploadChequePhoto('Paolo Garcia', Uint8List(0));
    expect(adminState.chequesWithNewPhotos.length, before + 1);
    expect(adminState.chequesNeedingPhoto('Paolo Garcia'), isNot(contains(c)));
    // Saving on the cheque's screen marks the photo checked, even with no
    // status change.
    adminState.setChequeStatus(c, c.status);
    expect(c.newPhoto, isFalse);
    appState.currentTenant = 'Juan Dela Cruz';
  });

  testWidgets('a cheque photo reaches management, who verify it on its own screen', (tester) async {
    tester.view.physicalSize = const Size(600, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    // Leave the shared demo cheques as they were for the other tests.
    final saved = [
      for (final c in adminState.cheques) (c, c.status, c.photo, c.uploadedOn, c.photoChecked)
    ];
    final paidUntil = adminState.tenants.firstWhere((t) => t.name == 'Paolo Garcia').paidUntil;
    addTearDown(() {
      adminState.cheques
        ..clear()
        ..addAll(saved.map((s) => s.$1
          ..status = s.$2
          ..photo = s.$3
          ..uploadedOn = s.$4
          ..photoChecked = s.$5));
      adminState.tenants.firstWhere((t) => t.name == 'Paolo Garcia').paidUntil = paidUntil;
    });
    // The tenant's photo goes on the first cheque still waiting for one.
    final waiting = adminState.chequeAwaitingPhoto('Paolo Garcia')!;
    final c = adminState.uploadChequePhoto('Paolo Garcia', Uint8List(0));
    expect(c, same(waiting));
    expect(c.uploadedOn, isNotNull);

    await tester.pumpWidget(MaterialApp(home: ChequeDetailScreen(c)));
    await tester.pumpAndSettle();
    expect(find.text('Verify'), findsOneWidget);
    expect(find.text('Cheque number'), findsOneWidget);
    expect(find.text('Bounced'), findsOneWidget);
    await tester.tap(find.text('Bounced'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save verification'));
    await tester.pumpAndSettle();
    expect(c.status, ChequeStatus.bounced);
  });

  testWidgets('a villa tenant flips between cheque years with the arrows', (tester) async {
    tester.view.physicalSize = const Size(600, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: ChequesScreen('Paolo Garcia')));
    await tester.pumpAndSettle();
    // Opens on the current lease year, 2025-2026, with its 4 cheques.
    expect(find.text('2025-2026'), findsOneWidget);
    expect(find.text('THIS YEAR'), findsOneWidget);
    // The next year has no cheques yet, but the arrow still works.
    await tester.tap(find.byTooltip('Next year'));
    await tester.pumpAndSettle();
    expect(find.text('2026-2027'), findsOneWidget);
    expect(find.text('THIS YEAR'), findsNothing);
    expect(find.textContaining('No cheques for this year yet'), findsOneWidget);
    await tester.tap(find.byTooltip('Previous year'));
    await tester.pumpAndSettle();
    expect(find.text('2025-2026'), findsOneWidget);
  });

  test('a cleared cheque becomes a payment and the tenant hears about each step', () {
    final keep = [...adminState.cheques];
    addTearDown(() => adminState.cheques
      ..clear()
      ..addAll(keep));
    final paolo = adminState.tenants.firstWhere((t) => t.name == 'Paolo Garcia');
    adminState.addCheque(paolo.name, ChequeKind.postDated, 66000, DateTime(2027, 2, 15), months: 3);
    final c = adminState.cheques.last;
    final aedBefore = adminState.collected(dhs: true);
    final paymentsBefore = adminState.payments.length;
    String latest() => adminState.notices.first.title;

    adminState.setChequeStatus(c, ChequeStatus.deposited);
    expect(latest(), 'Cheque deposited');
    adminState.setChequeStatus(c, ChequeStatus.cleared);
    expect(latest(), 'Cheque cleared');
    // Recorded as a verified AED payment.
    expect(adminState.payments.length, paymentsBefore + 1);
    final p = adminState.payments.first;
    expect(p.status, PayStatus.verified);
    expect(p.method, startsWith('Cheque'));
    expect(adminState.collected(dhs: true), aedBefore + c.amount);
    // Clearing again does not record it twice.
    adminState.setChequeStatus(c, ChequeStatus.cleared);
    expect(adminState.payments.length, paymentsBefore + 1);

    // A cheque dated in 2 days gets one reminder.
    adminState.addCheque('Paolo Garcia', ChequeKind.postDated, 1000,
        appState.today.add(const Duration(days: 2)), months: 1);
    adminState.sendChequeReminders();
    expect(latest(), 'Cheque date coming up');
    final count = adminState.notices.length;
    adminState.sendChequeReminders();
    expect(adminState.notices.length, count);

    // Planning cheques tells the tenant.
    adminState.planCheques(paolo, 3, yearStart: DateTime(2027, 11, 15));
    expect(latest(), 'Cheques for 2027-2028');
  });

  testWidgets('renewing a villa lease keeps history, sets up cheques and tells the tenant', (tester) async {
    tester.view.physicalSize = const Size(600, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final paolo = adminState.tenants.firstWhere((t) => t.name == 'Paolo Garcia');
    // Saved so the other tests see the original lease.
    final was = (paolo.leaseStart, paolo.leaseEnd, paolo.rent, paolo.chequesPerYear,
        paolo.contractName, paolo.contractPdf);
    final keep = [...adminState.cheques];
    addTearDown(() {
      paolo
        ..leaseStart = was.$1
        ..leaseEnd = was.$2
        ..rent = was.$3
        ..chequesPerYear = was.$4
        ..contractName = was.$5
        ..contractPdf = was.$6;
      paolo.pastLeases.clear();
      paolo.nextLease = null;
      paolo.endReminded = true;
      adminState.cheques
        ..clear()
        ..addAll(keep);
    });

    // Ends Nov 14, 2026: flagged for renewal, and the tenant was reminded.
    expect(adminState.leasesEndingWithin(60), contains(paolo));
    expect(adminState.notices.any((n) => n.to == 'Paolo Garcia' && n.title.startsWith('Your lease ends')), isTrue);

    await tester.pumpWidget(MaterialApp(home: RenewLeaseScreen(paolo)));
    await tester.pumpAndSettle();
    // Starts the day after the current lease and runs a year.
    expect(find.text('Nov 15, 2026'), findsWidgets);
    expect(find.text('Nov 14, 2027'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField).first, '25000');
    await tester.tap(find.text('3'));
    await tester.pump();
    await tester.tap(find.widgetWithText(GoldButton, 'Renew lease'));
    await tester.pumpAndSettle();

    // Agreed early: the current lease stays until Nov 14, the renewal waits.
    expect(paolo.leaseEnd, was.$2);
    expect(paolo.rent, was.$3);
    expect(paolo.nextLease?.start, 'Nov 15, 2026');
    expect(adminState.notices.any((n) => n.to == 'Paolo Garcia' && n.title == 'Lease renewal confirmed'), isTrue);
    // On Nov 15 it takes over by itself.
    adminState.applyDueRenewals(on: DateTime(2026, 11, 15));
    expect(paolo.nextLease, isNull);
    expect(paolo.leaseStart, 'Nov 15, 2026');
    expect(paolo.leaseEnd, 'Nov 14, 2027');
    expect(paolo.rent, 25000);
    expect(paolo.chequesPerYear, 3);
    expect(paolo.pastLeases.first.end, was.$2);
    expect(paolo.pastLeases.first.rent, was.$3);
    // Three cheques of 4 months each for the new year.
    final next = adminState.chequesFor('Paolo Garcia').where((c) =>
        c.kind == ChequeKind.postDated && !c.date.isBefore(DateTime(2026, 11, 15))).toList();
    expect(next.map((c) => c.date),
        [DateTime(2026, 11, 15), DateTime(2027, 3, 15), DateTime(2027, 7, 15)]);
    expect(next.first.amount, 100000);
    expect(adminState.leasesEndingWithin(60), isNot(contains(paolo)));
  });

  test('signing in loads that tenant\'s own profile, rent and reports', () {
    addTearDown(() => adminState.signInTenant('Juan Dela Cruz'));
    final juanTickets = appState.tickets.length;
    adminState.signInTenant('Paolo Garcia');
    expect(appState.currentTenant, 'Paolo Garcia');
    expect(appState.name, 'Paolo Garcia');
    expect(appState.unit, 'Villa 2 · Ayan Villas');
    expect(appState.monthlyRent, 24000);
    // Only Paolo's own reports, none of Juan's demo ones.
    final paoloReports = adminState.reports.where((r) => r.tenant == 'Paolo Garcia').length;
    expect(appState.tickets.length, paoloReports);
    // Back to Juan: his demo history returns.
    adminState.signInTenant('Juan Dela Cruz');
    expect(appState.unit, 'Unit 402 · Ayan Tower B');
    expect(appState.tickets.length, juanTickets);
  });

  testWidgets('sheet buttons stay above the phone\'s navigation buttons', (tester) async {
    tester.view.physicalSize = const Size(600, 1200);
    tester.view.devicePixelRatio = 1;
    // A three-button navigation bar, 48 px high, at the bottom.
    tester.view.padding = const FakeViewPadding(bottom: 48);
    tester.view.viewPadding = const FakeViewPadding(bottom: 48);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showAppSheet(context,
                title: 'Sheet',
                builder: (_) => GoldButton(label: 'Last button', onPressed: () {})),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    final bottom = tester.getRect(find.widgetWithText(GoldButton, 'Last button')).bottom;
    expect(bottom, lessThanOrEqualTo(1200 - 48));
  });

  testWidgets('a condo is tracked by hand: stays on the Scheduling tab, costs on Overview', (tester) async {
    tester.view.physicalSize = const Size(600, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final keep = [...adminState.bookings];
    addTearDown(() {
      adminState.bookings
        ..clear()
        ..addAll(keep);
      adminState.refreshCondoStatuses();
    });
    final studio = adminState.units.firstWhere((u) => u.name == 'Studio 3');

    // Demo date Oct 26: Liza Cruz (Oct 25-27) is staying -> Occupied, with
    // her deposit on the Deposit card. Condo 7A's next guest is Nov 5.
    expect(studio.status, UnitStatus.occupied);
    final liza = adminState.currentBooking('Studio 3')!;
    expect(liza.guest, 'Liza Cruz');
    expect(liza.deposit, 2500);
    expect(adminState.units.firstWhere((u) => u.name == 'Condo 7A').status, UnitStatus.reserved);
    // Past stays keep their full record; only the unit moves on.
    final mark = adminState.bookingsFor('Studio 3').firstWhere((b) => b.checkIn == DateTime(2026, 10, 20, 14));
    expect(mark.guest, 'Mark Lim');
    expect(mark.phone, isNotEmpty);
    expect(mark.amount, 5000);

    // A stay checking in today counts as staying today (by day, not hour).
    final c7 = adminState.units.firstWhere((u) => u.name == 'Condo 7A');
    adminState.saveBooking(
        null,
        Booking(
            id: '',
            unit: 'Condo 7A',
            guest: 'Walk-in',
            phone: '0917',
            checkIn: DateTime(2026, 10, 26, 14),
            checkOut: DateTime(2026, 10, 28, 12),
            amount: 1000,
            deposit: 5000));
    expect(c7.status, UnitStatus.occupied);
    final walkIn = adminState.currentBooking('Condo 7A')!;
    expect(walkIn.guest, 'Walk-in');
    // Taking some of the deposit off.
    adminState.deductDeposit(walkIn, 1200, 'Broken glass');
    expect(walkIn.depositLeft, 3800);
    // With every stay gone, a condo is Vacant.
    for (final b in adminState.bookingsFor('Condo 7A')) {
      adminState.removeBooking(b);
    }
    expect(c7.status, UnitStatus.vacant);

    // Overlapping dates are caught; back-to-back stays are fine.
    expect(adminState.clashingBooking('Studio 3', DateTime(2026, 11, 15, 14), DateTime(2026, 11, 17, 12)), isNotNull);
    expect(adminState.clashingBooking('Studio 3', DateTime(2026, 11, 16, 14), DateTime(2026, 11, 18, 12)), isNull);
    // Stays show on the admin calendar.
    expect(adminState.calendarEvents.any((e) => e.title == 'Check-in · Anna Reyes'), isTrue);
    // October costs of the demo condo.
    expect(adminState.costsInMonth('Studio 3', DateTime(2026, 10)), 3849);

    await tester.pumpWidget(MaterialApp(home: UnitDetailScreen(studio)));
    await tester.pumpAndSettle();
    expect(find.text('Scheduling'), findsOneWidget);
    expect(find.text('Tenant'), findsNothing);
    expect(find.text('Operational cost'), findsOneWidget);
    expect(find.text('Payment status'), findsNothing);
    expect(find.text('Complaints'), findsNothing);
    expect(find.text('Unit details'), findsNothing);
    expect(find.text('Damage occurred'), findsOneWidget);
    expect(find.text('Stay calendar'), findsOneWidget);
    // Status shows the stay by date, not the guest's name.
    expect(find.text('Staying now'), findsOneWidget);
    expect(find.text('Liza Cruz'), findsNothing);

    // Tapping a booked day opens that stay's details.
    await tester.ensureVisible(find.text('26').last);
    await tester.tap(find.text('26').last);
    await tester.pumpAndSettle();
    expect(find.text('Stay details'), findsOneWidget);
    expect(find.text('Liza Cruz'), findsOneWidget);
    expect(find.text('GUEST IN'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Scheduling'));
    await tester.pumpAndSettle();
    expect(find.text('Staying now'), findsOneWidget);
    expect(find.text('Upcoming'), findsOneWidget);
    expect(find.text('Anna Reyes'), findsOneWidget);
    expect(find.text('Schedule a stay'), findsWidgets);
  });

  testWidgets('booking form fills amount and deposit; costs are listed by month', (tester) async {
    tester.view.physicalSize = const Size(600, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final studio = adminState.units.firstWhere((u) => u.name == 'Studio 3');

    // New stay: one night by default, amount = nights x nightly rate,
    // deposit = the unit's deposit. No Paid switch, no Notes.
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(child: BookingForm(studio)))));
    await tester.pumpAndSettle();
    expect(find.text('2500'), findsNWidgets(2)); // amount and deposit
    expect(find.textContaining('× 1 night'), findsOneWidget);
    expect(find.text('Security deposit (₱)'), findsOneWidget);
    expect(find.text('Paid'), findsNothing);
    expect(find.text('Notes (optional)'), findsNothing);
    expect(find.text('Upload a file'), findsOneWidget);

    // Operational costs: October first, then September with the arrow.
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(child: CostsSheet(studio)))));
    await tester.pumpAndSettle();
    expect(find.text('October 2026'), findsOneWidget);
    expect(find.text('5 costs · ₱3,849.00'), findsOneWidget);
    await tester.tap(find.byTooltip('Previous month'));
    await tester.pumpAndSettle();
    expect(find.text('September 2026'), findsOneWidget);
    expect(find.text('3 costs · ₱2,899.00'), findsOneWidget);
  });

  testWidgets('booking over another guest opens a window with the earliest free time', (tester) async {
    tester.view.physicalSize = const Size(600, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final studio = adminState.units.firstWhere((u) => u.name == 'Studio 3');
    // Oct 26 2 PM to Oct 27 12 PM runs into Liza Cruz (Oct 25 - Oct 27 12 PM).
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: SingleChildScrollView(child: BookingForm(studio, startDay: DateTime(2026, 10, 26))))));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, 'Test guest');
    await tester.tap(find.text('Schedule stay'));
    await tester.pumpAndSettle();
    expect(find.text('Not available'), findsOneWidget);
    expect(find.textContaining('Liza Cruz'), findsOneWidget);
    expect(find.text('EARLIEST AVAILABLE'), findsOneWidget);
    // Earliest check-in: when Liza checks out.
    expect(find.text('Tue, Oct 27 · 12:00 PM'), findsWidgets);
    await tester.tap(find.text('Use this time'));
    await tester.pumpAndSettle();
    expect(find.text('Not available'), findsNothing);
    expect(find.text('Tue, Oct 27 · 12:00 PM'), findsOneWidget);
  });

  testWidgets('Damage occurred lists deposit deductions by month', (tester) async {
    tester.view.physicalSize = const Size(600, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final studio = adminState.units.firstWhere((u) => u.name == 'Studio 3');
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(child: DamageSheet(studio)))));
    await tester.pumpAndSettle();
    // October 2026: two deductions on Studio 3's stays.
    expect(find.text('October 2026'), findsOneWidget);
    expect(find.text('₱2,000.00'), findsOneWidget);
    expect(find.text('Broken drinking glass and plate'), findsOneWidget);
    expect(find.text('Lost key card'), findsOneWidget);
    await tester.tap(find.byTooltip('Previous month'));
    await tester.pumpAndSettle();
    expect(find.text('September 2026'), findsOneWidget);
    expect(find.text('Stained bedsheet'), findsOneWidget);
    await tester.tap(find.byTooltip('Previous month'));
    await tester.pumpAndSettle();
    expect(find.text('No damage in August 2026.'), findsOneWidget);
  });

  testWidgets('the landlady files a report for a condo by hand', (tester) async {
    tester.view.physicalSize = const Size(600, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final before = adminState.reports.length;
    addTearDown(() => adminState.reports.removeWhere((r) => r.id.startsWith('MR-')));
    await tester.pumpWidget(const MaterialApp(home: ReportVerificationScreen(unit: 'Studio 3')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('New report'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(0), 'Broken lamp');
    await tester.enterText(find.byType(TextFormField).at(1), 'Bedside lamp knocked over.');
    await tester.tap(find.text('Save report'));
    await tester.pumpAndSettle();
    expect(adminState.reports.length, before + 1);
    final r = adminState.reports.first;
    expect(r.unit, 'Studio 3');
    expect(r.tenant, 'Management');
    expect(r.type, ReportType.damage);
    expect(find.text('Broken lamp'), findsOneWidget);
    // Apartments don't get the button: their tenants report from the app.
    await tester.pumpWidget(const MaterialApp(home: ReportVerificationScreen(unit: 'Unit 402')));
    await tester.pumpAndSettle();
    expect(find.text('New report'), findsNothing);
  });

  test('monthly rent charges are made from the lease on the due day', () {
    final grace = adminState.tenants.firstWhere((t) => t.name == 'Grace Santos');
    final keep = [...adminState.charges];
    final wasDue = grace.dueDay;
    addTearDown(() {
      grace.dueDay = wasDue;
      adminState.charges
        ..clear()
        ..addAll(keep);
    });
    // Running it again adds nothing new.
    final count = adminState.charges.length;
    adminState.generateRentCharges();
    expect(adminState.charges.length, count);
    // Villas pay by cheque and condos are tracked by hand: no rent charges.
    expect(adminState.charges.where((c) => c.tenant == 'Paolo Garcia' && c.title.endsWith('rent')), isEmpty);
    expect(adminState.charges.where((c) => c.tenant == 'Carlo Mendoza'), isEmpty);
    // Grace has paid up to Oct 31. With rent due on the 1st, November's
    // charge (due Nov 1, within 10 days of Oct 26) appears, for her rent.
    grace.dueDay = 1;
    adminState.generateRentCharges();
    final nov = adminState.charges.firstWhere((c) => c.tenant == 'Grace Santos' && c.title == 'November 2026 rent');
    expect(nov.due, 'Nov 1, 2026');
    expect(nov.amount, grace.rent);
    expect(nov.overdue, isFalse);
    // October was already paid, so no October charge was made for her.
    expect(adminState.charges.any((c) => c.tenant == 'Grace Santos' && c.title == 'October 2026 rent'), isFalse);
  });

  testWidgets('condo demo walk-through: book a stay, deduct a deposit, see the damage', (tester) async {
    tester.view.physicalSize = const Size(600, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final keepBookings = [...adminState.bookings];
    final liza = adminState.bookings.firstWhere((b) => b.guest == 'Liza Cruz');
    final keepDeductions = [...liza.deductions];
    addTearDown(() {
      adminState.bookings
        ..clear()
        ..addAll(keepBookings);
      liza.deductions
        ..clear()
        ..addAll(keepDeductions);
      adminState.refreshCondoStatuses();
    });
    final studio = adminState.units.firstWhere((u) => u.name == 'Studio 3');
    await tester.pumpWidget(MaterialApp(home: UnitDetailScreen(studio)));
    await tester.pumpAndSettle();

    // 1. Schedule a stay from the Scheduling tab (default: tomorrow 2 PM to
    //    the next day 12 PM, right after Liza checks out).
    await tester.tap(find.text('Scheduling'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(GoldButton, 'Schedule a stay'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, 'Demo Guest');
    await tester.ensureVisible(find.text('Schedule stay'));
    await tester.tap(find.text('Schedule stay'));
    await tester.pumpAndSettle();
    expect(find.text('Not available'), findsNothing);
    expect(adminState.bookingsFor('Studio 3').any((b) => b.guest == 'Demo Guest' && b.deposit == 2500), isTrue);
    expect(find.text('Demo Guest'), findsOneWidget);

    // 2. Overview: the Deposit card is Liza's (staying now); deduct from it.
    await tester.tap(find.text('Overview'));
    await tester.pumpAndSettle();
    expect(find.text('₱2,500.00'), findsWidgets);
    await tester.tap(find.text('held · tap to deduct'));
    await tester.pumpAndSettle();
    expect(find.text('Left to return'), findsOneWidget);
    // Too much is refused in a window, not a hidden message.
    await tester.enterText(find.byType(TextField).at(0), '9000');
    await tester.tap(find.text('Deduct'));
    await tester.pumpAndSettle();
    expect(find.text('Too much'), findsOneWidget);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), '700');
    await tester.enterText(find.byType(TextField).at(1), 'Burnt pot');
    await tester.tap(find.text('Deduct'));
    await tester.pumpAndSettle();
    expect(liza.depositLeft, 1800);
    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();

    // 3. Damage occurred lists it for October.
    await tester.tap(find.text('Damage occurred'));
    await tester.pumpAndSettle();
    expect(find.text('Burnt pot'), findsOneWidget);
  });

  testWidgets('Finance covers a month, a year or custom dates, with condo usage', (tester) async {
    tester.view.physicalSize = const Size(600, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: FinanceScreen())));
    await tester.pumpAndSettle();
    expect(find.text('October 2026'), findsOneWidget);
    expect(find.text('Condo usage · October 2026'), findsOneWidget);
    expect(find.text('Apartment usage · October 2026'), findsOneWidget);
    expect(find.text('Villa usage · October 2026'), findsOneWidget);
    // Summary first; each unit only after "Show each unit".
    expect(find.text('Unit 402'), findsNothing);
    await tester.tap(find.text('Show each unit').at(1));
    await tester.pumpAndSettle();
    expect(find.text('Unit 402'), findsOneWidget);
    // Taxes (set rates) are listed and come off the profit.
    expect(find.text('Taxes'), findsOneWidget);
    expect(find.text('Total tax'), findsOneWidget);
    expect(find.textContaining('Percentage tax (3% of peso revenue)'), findsOneWidget);
    // Studio 3 in October: Rico (3 nights), Mark (2), Liza (2), Carlo (2 of 3).
    expect(find.text('Times used'), findsWidgets);
    // A whole year.
    await tester.tap(find.text('Year'));
    await tester.pumpAndSettle();
    expect(find.text('2026'), findsOneWidget);
    expect(find.text('NET PROFIT · 2026'), findsOneWidget);
    await tester.tap(find.byTooltip('Previous'));
    await tester.pumpAndSettle();
    expect(find.text('2025'), findsOneWidget);
    // Custom dates show the range and its length.
    await tester.tap(find.text('Custom'));
    await tester.pumpAndSettle();
    expect(find.textContaining('days · tap to change'), findsOneWidget);
  });

  test('the finance report builds as a PDF', () async {
    expect(pdfMoney(31118), 'PHP 31,118.00');
    expect(pdfMoney(72000, aed: true), 'AED 72,000.00');
    final bytes = await buildFinancePdf(
      period: 'October 2026',
      previousPeriod: 'September 2026',
      generatedOn: 'Oct 26, 2026',
      netPeso: pdfMoney(31118),
      netVillas: pdfMoney(0, aed: true),
      comparison: '+127% vs September 2026',
      statements: [
        (
          title: 'Apartments and condos',
          currency: 'Philippine pesos (PHP)',
          lines: [
            heading('Income'),
            line('Condo stays', 28267, 12000),
            total('Net profit', 31118, 13700),
          ],
        ),
      ],
      ratios: [(label: 'Net margin', now: '90%', before: '80%')],
      tables: [
        (title: 'By unit', columns: ['Unit', 'Net'], rows: [['Studio 3', pdfMoney(28267)]]),
      ],
    );
    // A real PDF file.
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    expect(bytes.length, greaterThan(1000));
  });

  test('a unit\'s condition follows the work scheduled in it', () {
    UnitRec unit(String n) => adminState.units.firstWhere((u) => u.name == n);
    // Demo date Oct 26: Villa 2 has a repair running, Condo 7A maintenance.
    expect(unit('Villa 2').condition, UnitCondition.underRepair);
    expect(unit('Condo 7A').condition, UnitCondition.underMaintenance);
    expect(unit('Unit 402').condition, UnitCondition.good);
    expect(adminState.activeWork(unit('Villa 2'))!.title, 'Bathroom tiles regrouting');

    // Scheduling a repair for today flips it; finishing it puts it back.
    final job = WorkItem(
        date: appState.today, time: '9:00 AM', title: 'Fix door', where: 'Unit 2B', kind: AdminEventKind.repair);
    adminState.scheduleWork(job);
    expect(unit('Unit 2B').condition, UnitCondition.underRepair);
    adminState.setWorkDone(job, true);
    expect(unit('Unit 2B').condition, UnitCondition.good);
    adminState.removeWork(job);

    // An inspection, or work in a later week, does not change it.
    final later = WorkItem(
        date: appState.today.add(const Duration(days: 7)), time: '9:00 AM', title: 'Paint', where: 'Unit 2B', kind: AdminEventKind.maintenance);
    final check = WorkItem(
        date: appState.today, time: '9:00 AM', title: 'Check', where: 'Unit 2B', kind: AdminEventKind.inspection);
    adminState.scheduleWork(later);
    adminState.scheduleWork(check);
    expect(unit('Unit 2B').condition, UnitCondition.good);
    adminState.removeWork(later);
    adminState.removeWork(check);
  });

  test('admin approves a document or asks for a new one', () {
    final paolo = adminState.tenants.firstWhere((t) => t.name == 'Paolo Garcia');
    addTearDown(() {
      paolo.docs['Visa'] = true;
      paolo.docVerified.remove('Visa');
      paolo.docRejected.remove('Visa');
    });
    // Paolo's visa is uploaded and waiting.
    expect(adminState.docState(paolo, 'Visa'), DocState.toReview);
    expect(adminState.docsToReview, greaterThan(0));
    adminState.rejectDocument(paolo, 'Visa', 'the photo is blurred');
    expect(adminState.docState(paolo, 'Visa'), DocState.rejected);
    expect(adminState.notices.first.title, 'Please upload your Visa again');
    adminState.uploadDocument('Paolo Garcia', 'Visa', 'visa.jpg', Uint8List(4));
    expect(adminState.docState(paolo, 'Visa'), DocState.toReview);
    adminState.verifyDocument(paolo, 'Visa');
    expect(adminState.docState(paolo, 'Visa'), DocState.verified);
  });

  test('an announcement can go to one unit type only', () {
    final before = adminState.notices.length;
    adminState.publishNotice('Villa pool cleaning', 'Friday 9 AM.', NoticeKind.general,
        types: {'Villa'});
    final n = adminState.notices.first;
    expect(adminState.notices.length, before + 1);
    expect(n.recipients, ['Paolo Garcia']);
    // Juan (apartment) does not see it; Paolo (villa) does.
    appState.currentTenant = 'Juan Dela Cruz';
    expect(appState.notices.any((x) => x.title == 'Villa pool cleaning'), isFalse);
    appState.currentTenant = 'Paolo Garcia';
    expect(appState.notices.any((x) => x.title == 'Villa pool cleaning'), isTrue);
    appState.currentTenant = 'Juan Dela Cruz';
    // Condos can be included now.
    // Condo guests have no app accounts, so no tenants live in condos.
    expect(adminState.tenantsOfTypes({'Condo'}), isEmpty);
    // Automatic notices are not announcements.
    expect(adminState.announcements.every((a) => !a.automatic), isTrue);
  });

  test('villa cheques are planned per lease year without doubling up', () {
    final paolo = adminState.tenants.firstWhere((t) => t.name == 'Paolo Garcia');
    // Lease starts Nov 15, 2025: that year and the next (for a renewal).
    final years = adminState.leaseYears(paolo);
    expect(years, contains(DateTime(2025, 11, 15)));
    expect(years.first, DateTime(2023, 11, 15)); // past years with cheques
    expect(years, contains(DateTime(2026, 11, 15)));
    expect(adminState.leaseYearOf(paolo, DateTime(2026, 8, 15)), DateTime(2025, 11, 15));
    expect(adminState.leaseYearOf(paolo, DateTime(2026, 11, 15)), DateTime(2026, 11, 15));

    // Re-planning a year whose cheques are already banked adds nothing.
    final before = adminState.chequesFor('Paolo Garcia').length;
    adminState.planCheques(paolo, 4, yearStart: DateTime(2025, 11, 15));
    expect(adminState.chequesFor('Paolo Garcia').length, before);

    // The next year: 2 cheques of 6 months each.
    adminState.planCheques(paolo, 2, yearStart: DateTime(2026, 11, 15));
    final held = adminState.chequesFor('Paolo Garcia').where((c) =>
        c.status == ChequeStatus.held && c.kind == ChequeKind.postDated).toList();
    expect(held.map((c) => c.date), [DateTime(2026, 11, 15), DateTime(2027, 5, 15)]);
    expect(held.first.amount, paolo.rent * 6);
    final until = paolo.paidUntil!;
    adminState.setChequeStatus(held.first, ChequeStatus.cleared);
    expect(paolo.paidUntil, addMonthsToPaidUntil(until, 6));
  });
  test('a due day past the end of a short month falls on its last day', () {
    expect(dueDateIn(2026, 2, 31), DateTime(2026, 2, 28));
    expect(dueDateIn(2028, 2, 30), DateTime(2028, 2, 29));
    expect(dueDateIn(2026, 4, 31), DateTime(2026, 4, 30));
    expect(dueDateIn(2026, 12, 31), DateTime(2026, 12, 31));
    expect(dueDateIn(2026, 2, 5), DateTime(2026, 2, 5));
  });

  test('paid-until math follows month ends and mid-month dates', () {
    expect(addMonthsToPaidUntil(DateTime(2026, 9, 30), 1), DateTime(2026, 10, 31));
    expect(addMonthsToPaidUntil(DateTime(2026, 9, 30), 2), DateTime(2026, 11, 30));
    expect(addMonthsToPaidUntil(DateTime(2026, 1, 31), 1), DateTime(2026, 2, 28));
    expect(addMonthsToPaidUntil(DateTime(2026, 11, 14), 3), DateTime(2027, 2, 14));
    expect(addMonthsToPaidUntil(DateTime(2026, 12, 31), 12), DateTime(2027, 12, 31));
  });

  test('a proof for several months extends the stay by that many months', () {
    appState.currentTenant = 'Juan Dela Cruz';
    final juan = adminState.tenants.firstWhere((t) => t.name == 'Juan Dela Cruz');
    final until = juan.paidUntil!;
    final from = until.add(const Duration(days: 1));
    final to = addMonthsToPaidUntil(until, 3);
    final before = adminState.payments.length;

    appState.submitPayment(
        method: 'GCash', amount: juan.rent * 3, reference: '7788', months: 3, from: from, to: to);
    expect(adminState.payments.length, before + 1);
    final p = adminState.payments.first;
    expect(p.status, PayStatus.submitted);
    expect(p.months, 3);
    expect(p.amount, juan.rent * 3);
    expect(p.coversFrom, from);
    expect(p.title, 'Rent · 3 months');
    // Nothing changes until management verifies it.
    expect(juan.paidUntil, until);

    adminState.verifyPayment(p);
    expect(juan.paidUntil, to);
    expect(p.status, PayStatus.verified);

    // Put the demo data back.
    juan.paidUntil = until;
    adminState.payments.remove(p);
    appState.payments.removeAt(0);
    appState.currentRentSubmitted = false;
  });

  testWidgets('a villa tenant is asked for Passport, Visa, EID and Ejari, with no deposit', (tester) async {
    tester.view.physicalSize = const Size(600, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final paolo = adminState.tenants.firstWhere((t) => t.name == 'Paolo Garcia');
    final juan = adminState.tenants.firstWhere((t) => t.name == 'Juan Dela Cruz');
    expect(adminState.requiredDocs(paolo), ['Passport', 'Visa', 'EID', 'Ejari']);
    expect(adminState.requiredDocs(juan), tenantDocs);

    appState.currentTenant = 'Paolo Garcia';
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: MoreScreen())));
    await tester.pumpAndSettle();
    expect(find.text('Passport'), findsOneWidget);
    expect(find.text('Visa'), findsOneWidget);
    expect(find.text('EID'), findsOneWidget);
    expect(find.text('Ejari'), findsOneWidget);
    expect(find.text('SECURITY DEPOSIT'), findsNothing);
    expect(find.text('Barangay clearance'), findsNothing);
    expect(find.text('2/4'), findsOneWidget);
    appState.currentTenant = 'Juan Dela Cruz';
  });

  test('a tenant uploads required documents and lease dates reach the calendars', () {
    appState.currentTenant = 'Juan Dela Cruz';
    final juan = adminState.tenants.firstWhere((t) => t.name == 'Juan Dela Cruz');
    expect(tenantDocs, ['Valid ID', 'ID picture', 'Barangay clearance', 'Police clearance', 'NBI clearance']);
    expect(juan.docs['Police clearance'], isFalse);
    adminState.uploadDocument('Juan Dela Cruz', 'Police clearance', 'police.pdf', Uint8List(10));
    expect(juan.docs['Police clearance'], isTrue);
    expect(juan.docFiles['Police clearance']!.name, 'police.pdf');
    juan.docs['Police clearance'] = false;
    juan.docFiles.remove('Police clearance');

    // Admin calendar: move-in and lease end come from the lease dates.
    final titles = adminState.calendarEvents.map((e) => e.title).toList();
    expect(titles, contains('Move-in · Juan Dela Cruz'));
    expect(titles, contains('Lease ends · Juan Dela Cruz'));

    // Changing the lease moves the tenant's own calendar entries too.
    final end = juan.leaseEnd;
    adminState.updateLease(juan,
        start: DateTime(2026, 1, 1), end: DateTime(2027, 3, 31), rent: juan.rent, dueDay: 5, deposit: juan.deposit);
    final ends = appState.events.where((e) => e.title == 'Lease ends').toList();
    expect(ends.length, 1);
    expect(ends.first.date, DateTime(2027, 3, 31));
    adminState.updateLease(juan,
        start: DateTime(2026, 1, 1), end: parseDate(end)!, rent: juan.rent, dueDay: 5, deposit: juan.deposit);
  });

  test('a report keeps the type the tenant chose', () {
    appState.currentTenant = 'Juan Dela Cruz';
    appState.addTicket(
        issue: 'Cracked tile', description: 'Bathroom', attachments: 0, type: ReportType.damage);
    final r = adminState.reports.first;
    expect(r.type, ReportType.damage);
    adminState.reports.remove(r);
    appState.tickets.removeWhere((t) => t.id == r.id);
  });

  testWidgets('tenant screen has Property Maintenance, Complaint and Modification tabs', (tester) async {
    tester.view.physicalSize = const Size(600, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const MaterialApp(home: MaintenanceScreen()));
    expect(find.text('Property Maintenance'), findsOneWidget);
    expect(find.text('Updates from management'), findsOneWidget);
    expect(find.text('Add photo'), findsWidgets);
    await tester.tap(find.text('Complaint'));
    await tester.pumpAndSettle();
    expect(find.text('Your complaints'), findsOneWidget);
    expect(find.text('Management replied'), findsOneWidget);
  });

  testWidgets('ghost cards show while loading, then the content fades in', (tester) async {
    demoLoadDelay = const Duration(milliseconds: 300);
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: LoadingSwitch(skeleton: SkeletonCards(), child: Text('Loaded content')),
      ),
    ));
    expect(find.byType(Bone), findsWidgets);
    expect(find.text('Loaded content'), findsNothing);
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Loaded content'), findsOneWidget);
    expect(find.byType(Bone), findsNothing);

    // The empty and error states render their text and actions.
    var retried = false;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: ErrorState(onRetry: () => retried = true)),
    ));
    await tester.tap(find.text('Try again'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(retried, isTrue);
  });

  test('a notice for one unit reaches only that tenant', () {
    final juan = adminState.tenants.firstWhere((t) => t.name == 'Juan Dela Cruz');
    adminState.notifyTenant(juan, 'Payment reminder', 'Total unpaid');
    appState.currentTenant = 'Juan Dela Cruz';
    expect(appState.notices.first.title, 'Payment reminder');
    appState.currentTenant = 'Grace Santos';
    expect(appState.notices.any((n) => n.title == 'Payment reminder'), isFalse);
    appState.currentTenant = 'Juan Dela Cruz';
    // Clean up so the other tests see the usual notices.
    appState.allNotices.removeWhere((n) => n.title == 'Payment reminder');
    adminState.notices.removeWhere((n) => n.title == 'Payment reminder');
  });

  testWidgets('a unit template fills the Add unit form', (tester) async {
    tester.view.physicalSize = const Size(600, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const MaterialApp(home: UnitsScreen()));
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    expect(find.text('Start from a template'), findsOneWidget);
    await tester.tap(find.text('Villa · 3 bedrooms'));
    await tester.pumpAndSettle();
    expect(find.text('Ayan Villas'), findsOneWidget);
    expect(find.text('22000'), findsOneWidget);
    expect(find.text('3 bedrooms'), findsOneWidget);

    // Save the settings as a new template.
    await tester.tap(find.byIcon(Icons.bookmark_add_outlined));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'Villa copy');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(adminState.unitTemplates.any((t) => t.name == 'Villa copy'), isTrue);
    expect(tester.takeException(), isNull);
    // The new template's chip comes first in the strip.
    expect(find.text('Villa copy'), findsOneWidget);
  });

  testWidgets('admin login and core admin flows', (tester) async {
    tester.view.physicalSize = const Size(600, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const AyanApp());
    await tester.tap(find.text('Login'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(0), '1234');
    await tester.enterText(find.byType(TextFormField).at(1), '1234');
    await tester.tap(find.text('Log In'));
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle(const Duration(seconds: 1));

    // Admin dashboard.
    expect(find.text('Needs your attention'), findsOneWidget);

    // The Scheduling card opens the scheduling screen.
    await tester.tap(find.text('Scheduling'));
    await tester.pumpAndSettle();
    expect(find.text('Scheduling'), findsOneWidget);
    expect(find.text('Schedule'), findsWidgets);
    await tester.pageBack();
    await tester.pumpAndSettle();

    // Verify a payment from the dashboard card.
    await tester.tap(find.text('PAYMENT VERIFICATION'));
    await tester.pumpAndSettle();
    expect(find.text('Verify'), findsWidgets);
    expect(find.text('Record payment'), findsOneWidget);
    await tester.tap(find.text('Record payment'));
    await tester.pumpAndSettle();
    expect(find.text('Payment is for'), findsOneWidget);
    expect(find.text('Record and mark paid'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Verify').first);
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();

    // Accounts: open one, then create a new one.
    await tester.tap(find.text('Accounts'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Juan Dela Cruz'));
    await tester.pumpAndSettle();
    expect(find.text('Signed lease'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('New'));
    await tester.pumpAndSettle();
    expect(find.text('Create account'), findsWidgets);
    await tester.enterText(find.byType(TextFormField).at(0), 'Test Tenant');
    await tester.tap(find.text('Generate username and password'));
    await tester.pumpAndSettle();
    final createBtn = find.widgetWithText(GoldButton, 'Create account');
    await tester.ensureVisible(createBtn);
    await tester.pumpAndSettle();
    await tester.tap(createBtn, warnIfMissed: true);
    await tester.pumpAndSettle();
    final made = adminState.tenants.where((t) => t.name == 'Test Tenant');
    expect(made.length, 1);
    // A ready account: no unit assigned yet.
    expect(made.first.unit, '');
  });

  test('a part-payment leaves the charge open with the rest owed', () {
    final grace = adminState.tenants.firstWhere((t) => t.name == 'Grace Santos');
    final payments = adminState.payments.length;
    adminState.addCharge(grace.name, 'Test parking', 1000, 'Oct 30, 2026');
    final c = adminState.charges.first;
    addTearDown(() {
      adminState.charges.remove(c);
      adminState.payments.removeRange(0, adminState.payments.length - payments);
    });
    adminState.recordPayment(grace, charge: c, amount: 400, method: 'Cash', reference: '', date: 'Oct 26, 2026');
    expect(c.paid, isFalse);
    expect(c.partlyPaid, isTrue);
    expect(c.remaining, 600);
    adminState.recordPayment(grace, charge: c, amount: 600, method: 'Cash', reference: '', date: 'Oct 26, 2026');
    expect(c.paid, isTrue);
    expect(c.remaining, 0);
  });

  test('a bounced cheque gets a replacement and the fee', () {
    final keep = [...adminState.cheques];
    final charges = adminState.charges.length;
    final c = adminState.cheques.firstWhere((x) => x.id == 'CH-5');
    final was = c.status;
    addTearDown(() {
      c.status = was;
      adminState.cheques
        ..clear()
        ..addAll(keep);
      adminState.charges.removeRange(0, adminState.charges.length - charges);
    });
    adminState.setChequeStatus(c, ChequeStatus.bounced);
    final replacement = adminState.cheques.last;
    expect(replacement.replaces, 'CH-5');
    expect(replacement.amount, c.amount);
    expect(replacement.status, ChequeStatus.held);
    expect(adminState.charges.first.title, startsWith('Bounced cheque fee'));
    expect(adminState.charges.first.amount, adminState.bouncedChequeFee);
  });

  test('moving out settles the deposit, frees the unit and keeps a record', () {
    final unit = adminState.units.firstWhere((u) => u.name == 'Unit 2B');
    final t = TenantRec(
        name: 'Test Mover', unit: 'Unit 2B', phone: '1', email: 'a@b.c', stayType: 'Monthly', rent: 8000,
        leaseStart: 'Jan 01, 2026', leaseEnd: 'Dec 31, 2026', username: 'mover', password: 'x', deposit: 8000);
    adminState.createAccount(t);
    addTearDown(() {
      adminState.formerTenants.clear();
      adminState.charges.removeWhere((c) => c.tenant == 'Test Mover');
      unit
        ..status = UnitStatus.vacant
        ..tenant = null;
    });
    expect(unit.status, UnitStatus.occupied);
    adminState.addCharge(t.name, 'December 2026 rent', 8000, 'Dec 05, 2026');
    adminState.moveOut(t, date: DateTime(2026, 10, 31), deduction: 1500, reason: 'Broken cabinet', inspection: 'ok');
    expect(adminState.tenants.contains(t), isFalse);
    expect(unit.status, UnitStatus.vacant);
    // December rent is after the move-out, so it is dropped, not owed.
    expect(adminState.charges.any((c) => c.tenant == 'Test Mover'), isFalse);
    final f = adminState.formerTenants.first;
    expect(f.name, 'Test Mover');
    expect(f.depositNote, contains('6,500'));
    expect(f.owedAtMoveOut, 0);
  });

  test('work on a whole building puts its units under maintenance', () {
    final w = WorkItem(
        date: appState.today, time: 'All day', title: 'Test pump', where: 'Ayan Tower B', kind: AdminEventKind.maintenance);
    adminState.scheduleWork(w);
    addTearDown(() => adminState.removeWork(w));
    final unit = adminState.units.firstWhere((u) => u.name == 'Unit 2B');
    expect(unit.condition, UnitCondition.underMaintenance);
  });

  test('apartment status follows the lease: reserved, occupied, vacant', () {
    final unit = adminState.units.firstWhere((u) => u.name == 'Unit 2B');
    final t = TenantRec(
        name: 'Test Status', unit: 'Unit 2B', phone: '1', email: 'a@b.c', stayType: 'Monthly', rent: 8000,
        leaseStart: 'Dec 01, 2026', leaseEnd: 'Nov 30, 2027', username: 'status1', password: 'x');
    addTearDown(() {
      if (adminState.tenants.contains(t)) adminState.deleteAccount(t);
    });
    // Lease starts after today (Oct 26, 2026): reserved for them.
    adminState.createAccount(t);
    expect(unit.status, UnitStatus.reserved);
    expect(unit.tenant, 'Test Status');
    // The lease now starts before today: occupied.
    adminState.updateLease(t,
        start: DateTime(2026, 10, 1), end: DateTime(2027, 9, 30), rent: 8000, dueDay: 5, deposit: 8000);
    expect(unit.status, UnitStatus.occupied);
    // No tenant any more: vacant.
    adminState.deleteAccount(t);
    expect(unit.status, UnitStatus.vacant);
    expect(unit.tenant, isNull);
  });
}
