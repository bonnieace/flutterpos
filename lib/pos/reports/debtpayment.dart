import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class DebtPaymentsPage extends StatefulWidget {
  const DebtPaymentsPage({super.key});

  @override
  _DebtPaymentsPageState createState() => _DebtPaymentsPageState();
}

class _DebtPaymentsPageState extends State<DebtPaymentsPage> {
  late CollectionReference salesCollection;

  @override
  void initState() {
    super.initState();
    salesCollection = FirebaseFirestore.instance.collection('hwsales');
  }

  String normalizeCustomerName(String name) {
    return name.trim().toLowerCase();
  }

  Future<void> _showPaymentDialog(BuildContext context, String customerName, List<DocumentSnapshot> debtPayments) async {
    TextEditingController amountController = TextEditingController();
    return showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Enter Payment Amount'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: amountController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Payment Amount'),
              ),
            ],
          ),
          actions: [
            TextButton(
              child: const Text('Pay'),
              onPressed: () {
                Navigator.of(context).pop();
                _handlePayment(customerName, debtPayments, double.parse(amountController.text));
              },
            ),
          ],
        );
      },
    );
  }

  void _handlePayment(String customerName, List<DocumentSnapshot> debtPayments, double totalPayment) {
    for (var debtPayment in debtPayments) {
      double debtAmount = debtPayment['debtAmount'];
      if (totalPayment > 0) {
        if (totalPayment >= debtAmount) {
          updateDebt(debtPayment, 'Paid', debtAmount);
          totalPayment -= debtAmount;
        } else {
          updateDebt(debtPayment, 'Paid', totalPayment);
          totalPayment = 0;
        }
      }
    }
  }

  void updateDebt(DocumentSnapshot debtPayment, String paymentMethod, double paymentAmount) {
    double newDebtAmount = debtPayment['debtAmount'] - paymentAmount;
    salesCollection.doc(debtPayment.id).update({
      'payment': newDebtAmount <= 0 ? paymentMethod : 'Debt',
      'debtAmount': newDebtAmount < 0 ? 0 : newDebtAmount,
    });
  }

  String calculateDaysSince(DateTime paymentDate) {
    final currentDate = DateTime.now();
    final daysSince = currentDate.difference(paymentDate).inDays;
    return '$daysSince days';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Debt Payments',style: TextStyle(color: Colors.blue),),
        automaticallyImplyLeading: false,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: salesCollection.where('payment', isEqualTo: 'Debt').snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }

          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(child: Text('No debt payments found.'));
          }

          Map<String, List<DocumentSnapshot>> customerDebts = {};
          List<DocumentSnapshot> debtPaymentDocs = snapshot.data!.docs;

          for (var doc in debtPaymentDocs) {
            String customerName = normalizeCustomerName(doc['customer']);
            if (customerDebts.containsKey(customerName)) {
              customerDebts[customerName]!.add(doc);
            } else {
              customerDebts[customerName] = [doc];
            }
          }

          return ListView.builder(
            itemCount: customerDebts.keys.length,
            itemBuilder: (context, index) {
              String customerName = customerDebts.keys.elementAt(index);
              List<DocumentSnapshot> debts = customerDebts[customerName]!;
              double totalDebtAmount = debts.fold(0.0, (sum, doc) => sum + (doc['debtAmount'] ?? 0.0));

              return Card(
                child: ListTile(
                  title: Text('Customer: $customerName'),
                  subtitle: Text('Total Debt Amount: Ksh ${totalDebtAmount.toString()}'),
                  trailing: IconButton(
                    icon: const Icon(Icons.payment,color: Colors.blue,),
                    onPressed: () {
                      _showPaymentDialog(context, customerName, debts);
                    },
                  ),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => CustomerDebtDetailsPage(customerName: customerName, debts: debts),
                      ),
                    );
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class CustomerDebtDetailsPage extends StatelessWidget {
  final String customerName;
  final List<DocumentSnapshot> debts;

  const CustomerDebtDetailsPage({super.key, required this.customerName, required this.debts});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Debt Details for $customerName'),
      ),
      body: ListView.builder(
        itemCount: debts.length,
        itemBuilder: (context, index) {
          var debtPayment = debts[index];
          double paymentAmount = debtPayment['totalAmount'];
          DateTime paymentDate = (debtPayment['dateAdded'] as Timestamp).toDate();
          double debtAmount = debtPayment['debtAmount'] ?? 0.0;

          return Card(
            child: ListTile(
              title: Text('Payment Amount: Ksh ${paymentAmount.toString()}'),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Payment Date: ${paymentDate.toLocal()}'),
                  Text('Debt Amount: Ksh ${debtAmount.toString()}'),
                  Text('Days Unpaid: ${calculateDaysSince(paymentDate)}'),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  String calculateDaysSince(DateTime paymentDate) {
    final currentDate = DateTime.now();
    final daysSince = currentDate.difference(paymentDate).inDays;
    return '$daysSince days';
  }
}
