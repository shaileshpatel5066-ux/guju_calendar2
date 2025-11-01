import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  await Hive.initFlutter();
  await Hive.openBox('tasks');
  MobileAds.instance.initialize();
  runApp(const GujuApp());
}

class GujuApp extends StatelessWidget {
  const GujuApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.light,
        primarySwatch: Colors.deepOrange,
      ),
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        primarySwatch: Colors.deepOrange,
      ),
      themeMode: ThemeMode.system,
      home: const SplashScreen(),
    );
  }
}

/// ✅ Splash Screen
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override
  State<SplashScreen> createState() => _SplashState();
}

class _SplashState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(seconds: 2), () {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const AuthGate()),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Text("Guju Calendar",
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
      ),
    );
  }
}

/// ✅ Login / Auth
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});
  @override
  Widget build(BuildContext context) {
    return StreamBuilder(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        if (snap.hasData) return const HomePage();
        return const LoginScreen();
      },
    );
  }
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginState();
}

class _LoginState extends State<LoginScreen> {
  final phoneCtrl = TextEditingController();
  final otpCtrl = TextEditingController();
  String? verifyId;
  bool codeSent = false;

  sendOTP() async {
    await FirebaseAuth.instance.verifyPhoneNumber(
      phoneNumber: "+91" + phoneCtrl.text.trim(),
      verificationCompleted: (cred) async {
        await FirebaseAuth.instance.signInWithCredential(cred);
      },
      verificationFailed: (e) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message ?? 'Error')));
      },
      codeSent: (id, _) {
        setState(() {
          verifyId = id;
          codeSent = true;
        });
      },
      codeAutoRetrievalTimeout: (_) {},
    );
  }

  verifyOTP() async {
    try {
      final cred = PhoneAuthProvider.credential(
          verificationId: verifyId!, smsCode: otpCtrl.text.trim());
      await FirebaseAuth.instance.signInWithCredential(cred);
    } catch (_) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text("Invalid OTP")));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Login")),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          TextField(
            controller: phoneCtrl,
            decoration: const InputDecoration(labelText: "Mobile Number"),
            keyboardType: TextInputType.phone,
          ),
          if (codeSent)
            TextField(
              controller: otpCtrl,
              decoration: const InputDecoration(labelText: "OTP"),
              keyboardType: TextInputType.number,
            ),
          const SizedBox(height: 15),
          ElevatedButton(
            onPressed: codeSent ? verifyOTP : sendOTP,
            child: Text(codeSent ? "Verify OTP" : "Send OTP"),
          )
        ]),
      ),
    );
  }
}

/// ✅ Home Page with Calendar + Todo + Ads
class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomeState();
}

class _HomeState extends State<HomePage> {
  DateTime focused = DateTime.now();
  DateTime? selected;
  final box = Hive.box('tasks');
  final taskCtrl = TextEditingController();

  BannerAd? banner;

  @override
  void initState() {
    super.initState();
    banner = BannerAd(
      size: AdSize.banner,
      adUnitId: BannerAd.testAdUnitId,
      listener: const BannerAdListener(),
      request: const AdRequest(),
    )..load();
  }

  List tasksFor(DateTime date) {
    final key = date.toIso8601String().split("T")[0];
    return List.from(box.get(key) ?? []);
  }

  addTask() {
    if (selected == null || taskCtrl.text.isEmpty) return;
    final key = selected!.toIso8601String().split("T")[0];
    final list = tasksFor(selected!);
    list.add(taskCtrl.text.trim());
    box.put(key, list);
    taskCtrl.clear();
    setState(() {});
  }

  logout() => FirebaseAuth.instance.signOut();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Guju Calendar"),
        actions: [
          IconButton(onPressed: logout, icon: const Icon(Icons.logout))
        ],
      ),
      bottomNavigationBar: banner == null
          ? null
          : SizedBox(height: 50, child: AdWidget(ad: banner!)),
      body: Column(
        children: [
          TableCalendar(
            firstDay: DateTime(2000),
            lastDay: DateTime(2100),
            focusedDay: focused,
            selectedDayPredicate: (d) => isSameDay(d, selected),
            onDaySelected: (sel, foc) {
              setState(() {
                selected = sel;
                focused = foc;
              });
            },
          ),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Row(children: [
              Expanded(
                child: TextField(
                  controller: taskCtrl,
                  decoration: const InputDecoration(hintText: "Add task"),
                ),
              ),
              ElevatedButton(onPressed: addTask, child: const Text("Add")),
            ]),
          ),
          Expanded(
            child: selected == null
                ? const Center(child: Text("Select a date"))
                : ListView(
                    children: tasksFor(selected!)
                        .map((e) => ListTile(title: Text(e)))
                        .toList(),
                  ),
          )
        ],
      ),
    );
  }
}
