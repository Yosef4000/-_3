
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uuid/uuid.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  runApp(const IDChatApp());
}

class IDChatApp extends StatefulWidget {
  const IDChatApp({super.key});

  @override
  State<IDChatApp> createState() => _IDChatAppState();
}

class _IDChatAppState extends State<IDChatApp> {
  bool dark = false;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'ID Chat',
      themeMode: dark ? ThemeMode.dark : ThemeMode.light,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.teal,
        ),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.teal,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: StreamBuilder<User?>(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (context, snapshot) {
          if (snapshot.data == null) {
            return const LoginPage();
          }
          return HomePage(
            onTheme: (value) => setState(() => dark = value),
          );
        },
      ),
    );
  }
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final email = TextEditingController();
  final password = TextEditingController();
  String error = '';
  bool register = true;
  bool loading = false;

  Future<void> submit() async {
    setState(() {
      loading = true;
      error = '';
    });

    try {
      final auth = FirebaseAuth.instance;

      if (register) {
        final result =
            await auth.createUserWithEmailAndPassword(
          email: email.text.trim(),
          password: password.text,
        );

        final uid = result.user!.uid;
        final db = FirebaseFirestore.instance;
        final id = 'ID-${const Uuid().v4()
            .replaceAll('-', '').substring(0, 10).toUpperCase()}';

        // Register the ID and user in one database batch.
        final batch = db.batch();
        batch.set(db.collection('users').doc(uid), {
          'uid': uid,
          'publicId': id,
          'email': email.text.trim(),
          'displayName': email.text.trim().split('@').first,
          'createdAt': FieldValue.serverTimestamp(),
        });
        batch.set(db.collection('publicIds').doc(id), {
          'uid': uid,
          'createdAt': FieldValue.serverTimestamp(),
        });
        await batch.commit();
      } else {
        await auth.signInWithEmailAndPassword(
          email: email.text.trim(),
          password: password.text,
        );
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) setState(() => error = e.message ?? e.code);
    } catch (e) {
      if (mounted) {
        setState(() => error = 'حدث خطأ. تحقق من إعداد Firebase.');
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.forum, size: 75, color: Colors.teal),
              const Text('ID Chat',
                  style: TextStyle(fontSize: 30,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 25),
              TextField(
                controller: email,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'البريد الإلكتروني',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: password,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'كلمة المرور',
                  border: OutlineInputBorder(),
                ),
              ),
              if (error.isNotEmpty)
                Text(error, style: const TextStyle(color: Colors.red)),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: loading ? null : submit,
                child: Text(loading
                    ? 'يرجى الانتظار...'
                    : register ? 'إنشاء حساب' : 'تسجيل الدخول'),
              ),
              TextButton(
                onPressed: () => setState(() => register = !register),
                child: Text(register
                    ? 'لدي حساب بالفعل'
                    : 'إنشاء حساب جديد'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class HomePage extends StatefulWidget {
  final ValueChanged<bool> onTheme;

  const HomePage({super.key, required this.onTheme});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final idController = TextEditingController();
  String message = '';
  bool dark = false;

  final db = FirebaseFirestore.instance;

  Future<void> addById() async {
    final entered = idController.text.trim().toUpperCase();
    if (entered.isEmpty) return;

    try {
      final me = FirebaseAuth.instance.currentUser!;
      final idDoc = await db.collection('publicIds').doc(entered).get();

      if (!idDoc.exists) {
        setState(() => message = 'رقم ID غير موجود.');
        return;
      }

      final otherUid = idDoc.data()!['uid'] as String;

      if (otherUid == me.uid) {
        setState(() => message = 'هذا رقم ID الخاص بك.');
        return;
      }

      final members = [me.uid, otherUid]..sort();
      final chatId = '${members[0]}_${members[1]}';

      await db.collection('chats').doc(chatId).set({
        'members': members,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      idController.clear();
      if (mounted) {
        setState(() => message = 'تم إنشاء المحادثة بنجاح.');
      }
    } catch (_) {
      setState(() => message = 'تعذرت العملية. تحقق من الاتصال.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser!;

    return Scaffold(
      appBar: AppBar(
        title: const Text('ID Chat'),
        actions: [
          IconButton(
            icon: Icon(dark ? Icons.light_mode : Icons.dark_mode),
            onPressed: () {
              dark = !dark;
              widget.onTheme(dark);
              setState(() {});
            },
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => FirebaseAuth.instance.signOut(),
          ),
        ],
      ),
      body: Column(
        children: [
          StreamBuilder(
            stream: db.collection('users').doc(user.uid).snapshots(),
            builder: (context, snapshot) {
              final data = snapshot.data?.data();
              return ListTile(
                leading: const CircleAvatar(
                  child: Icon(Icons.person),
                ),
                title: const Text('رقم ID الخاص بك'),
                subtitle: SelectableText(
                  data?['publicId'] ?? 'جارٍ التحميل...',
                ),
              );
            },
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: idController,
                    decoration: const InputDecoration(
                      labelText: 'أدخل ID لإضافة مستخدم',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: addById,
                  child: const Text('إضافة'),
                ),
              ],
            ),
          ),
          Text(message),
          const Divider(),
          const ListTile(
            title: Text('المحادثات',
                style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          Expanded(
            child: StreamBuilder(
              stream: db.collection('chats')
                  .where('members', arrayContains: user.uid)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return const Center(
                      child: Text('خطأ في تحميل المحادثات'));
                }
                if (!snapshot.hasData) {
                  return const Center(
                      child: CircularProgressIndicator());
                }

                final chats = snapshot.data!.docs;

                if (chats.isEmpty) {
                  return const Center(
                    child: Text('أضف شخصاً باستخدام رقم ID'),
                  );
                }

                return ListView.builder(
                  itemCount: chats.length,
                  itemBuilder: (context, index) {
                    final chat = chats[index];
                    final members =
                        List<String>.from(chat.data()['members']);
                    final otherUid =
                        members.firstWhere((id) => id != user.uid);

                    return FutureBuilder(
                      future: db.collection('users').doc(otherUid).get(),
                      builder: (context, userSnapshot) {
                        final other = userSnapshot.data?.data();
                        return ListTile(
                          leading: const CircleAvatar(
                            child: Icon(Icons.person),
                          ),
                          title: Text(
                            other?['displayName'] ?? 'مستخدم',
                          ),
                          subtitle: Text(other?['publicId'] ?? ''),
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => ChatPage(
                                  chatId: chat.id,
                                  name: other?['displayName'] ?? 'محادثة',
                                ),
                              ),
                            );
                          },
                        );
                      },
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class ChatPage extends StatefulWidget {
  final String chatId;
  final String name;

  const ChatPage({
    super.key,
    required this.chatId,
    required this.name,
  });

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final controller = TextEditingController();
  final db = FirebaseFirestore.instance;

  Future<void> sendMessage() async {
    final text = controller.text.trim();
    if (text.isEmpty) return;

    final uid = FirebaseAuth.instance.currentUser!.uid;
    final chat = db.collection('chats').doc(widget.chatId);

    await chat.collection('messages').add({
      'senderId': uid,
      'text': text,
      'type': 'text',
      'createdAt': FieldValue.serverTimestamp(),
    });

    await chat.set({
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    controller.clear();
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser!.uid;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.name),
        actions: [
          IconButton(
            icon: const Icon(Icons.videocam),
            tooltip: 'مكالمة فيديو',
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'يلزم دمج خدمة مكالمات فيديو لتفعيل الاتصال.',
                  ),
                ),
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder(
              stream: db.collection('chats')
                  .doc(widget.chatId)
                  .collection('messages')
                  .orderBy('createdAt')
                  .snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(
                      child: CircularProgressIndicator());
                }

                final messages = snapshot.data!.docs;

                return ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final data = messages[index].data();
                    final mine = data['senderId'] == uid;

                    return Align(
                      alignment: mine
                          ? Alignment.centerRight
                          : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: mine
                              ? Theme.of(context)
                                  .colorScheme.primaryContainer
                              : Theme.of(context)
                                  .colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Text(data['text'] ?? ''),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: controller,
                      minLines: 1,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        hintText: 'اكتب رسالة...',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: sendMessage,
                    icon: const Icon(Icons.send),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}