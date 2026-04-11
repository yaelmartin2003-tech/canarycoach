import 'dart:async';
import 'dart:typed_data';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'dart:ui' show ImageFilter;
import 'package:shared_preferences/shared_preferences.dart';
import '../../utils/shell_nav_visibility.dart';
import '../../data/user_store.dart';
import '../../theme/app_theme.dart';
import '../../widgets/keyboard_input_preview.dart';

// Notifier global — AppShell lo escucha para mostrar el badge en la barra de nav
final ValueNotifier<int> chatUnreadNotifier = ValueNotifier(0);

// ---------------------------------------------------------------------------
// Data models
// ---------------------------------------------------------------------------

class _Message {
  const _Message({required this.text, required this.isAdmin, this.createdAt});
  final String text;
  final bool isAdmin; // true = enviado por el coach/admin (derecha, naranja)
  final DateTime? createdAt;
}

class _ChatUser {
  _ChatUser({
    required this.id,
    required this.name,
    required this.initial,
    required List<_Message> messages,
    this.createdAt,
    this.photoBytes,
    this.photoUrl = '',
    this.role = AppUserRole.user,
    this.trainerId,
  }) : messages = List<_Message>.from(messages);

  final String id;
  final String name;
  final String initial;
  final List<_Message> messages;
  final Uint8List? photoBytes;
  final String photoUrl;
  final AppUserRole role;
  final String? trainerId;
  final DateTime? createdAt;
  int unreadCount = 0;
}

// ---------------------------------------------------------------------------
// ChatPage
// ---------------------------------------------------------------------------

class ChatPage extends StatefulWidget {
  const ChatPage({super.key});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  _ChatUser? _openedUser;
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  AppUserRole get _role => UserStore.instance.currentUser.role;
  bool get _isAdmin => _role == AppUserRole.admin;
  bool get _isTrainer => _role == AppUserRole.trainer;
  bool get _isRegularUser => _role == AppUserRole.user || _role == AppUserRole.sinclave;
  String get _currentUserId => UserStore.instance.currentUser.id;

  // Construye la lista de chats visible según el rol
  List<_ChatUser> _buildChatList() {
    final currentId = _currentUserId;
    final all = UserStore.instance.users;

    if (_isAdmin) {
      // Admin ve entrenadores, usuarios marcados como 'sinclave',
      // además de sus propios usuarios asignados.
      return all
          .where((u) {
            if (u.id == currentId) return false;
            if (u.role == AppUserRole.trainer) return true;
            if (u.role == AppUserRole.sinclave) return true;
            if (u.role == AppUserRole.user) {
              // Mostrar usuarios sin trainer asignado (compatibilidad)
              final noTrainer = u.trainerId == null || u.trainerId!.trim().isEmpty;
              // Mostrar también usuarios asignados al admin
              final assignedToMe = u.trainerId == currentId;
              return noTrainer || assignedToMe;
            }
            return false;
          })
          .map(_toChatUser)
          .toList();
    }

    if (_isTrainer) {
      // Trainer ve solo sus usuarios asignados
      return all
          .where((u) =>
              u.id != currentId &&
              u.role == AppUserRole.user &&
              u.trainerId == currentId)
          .map(_toChatUser)
          .toList();
    }

    // Usuario normal: mostrar la tarjeta del entrenador solo si el rol es
    // `user` y además tiene `trainerId` vinculado. Para `sinclave` no
    // mostramos tarjetas en la lista (solo el FAB de admin en la UI).
    if (_isRegularUser) {
      final me = UserStore.instance.currentUser;
      final trainerId = (me.trainerId ?? '').trim();
      if (_role == AppUserRole.user && trainerId.isNotEmpty) {
        final trainer = all.where((u) => u.id == trainerId).firstOrNull;
        if (trainer != null) return [_toChatUser(trainer)];
      }
      return [];
    }
    return [];
  }

  _ChatUser _toChatUser(AppUserData u) => _ChatUser(
        id: u.id,
        name: u.name.isEmpty ? u.email : u.name,
        initial: (() {
          final b = (u.name.isEmpty ? u.email : u.name).trim();
          return b.isNotEmpty ? b.substring(0, 1).toUpperCase() : '?';
        })(),
        messages: const [],
        photoBytes: u.photoBytes,
        photoUrl: u.photoUrl,
        createdAt: u.createdAt,
        role: u.role,
        trainerId: u.trainerId,
      );

  // Chat con el admin (para trainers)
  _ChatUser get _adminChatUser => _buildAdminChatUser();

  _ChatUser _buildAdminChatUser() {
    final admin = UserStore.instance.users
        .where((u) => u.role == AppUserRole.admin)
        .firstOrNull;
    final name = admin?.name ?? 'Admin';
    return _ChatUser(
      id: admin?.id ?? '',
      name: name,
      initial: name.isNotEmpty ? name[0].toUpperCase() : 'A',
      messages: const [],
      photoBytes: admin?.photoBytes,
      photoUrl: admin?.photoUrl ?? '',
      createdAt: admin?.createdAt,
      role: AppUserRole.admin,
    );
  }

  // Chat del usuario con su entrenador
  _ChatUser get _trainerChatUser => _buildTrainerChatUser();

  _ChatUser _buildTrainerChatUser() {
    final me = UserStore.instance.currentUser;
    final trainerId = (me.trainerId ?? '').trim();
    // Si ya tenemos un objeto persistente para este interlocutor, retornarlo
    if (trainerId.isNotEmpty && _chatUserMap.containsKey(trainerId)) {
      return _chatUserMap[trainerId]!;
    }

    if (trainerId.isNotEmpty) {
      final trainer = UserStore.instance.users
          .where((u) => u.id == trainerId)
          .firstOrNull;
      final name = trainer?.name ?? 'Entrenador';
      final u = _ChatUser(
        id: trainerId,
        name: name,
        initial: name.isNotEmpty ? name[0].toUpperCase() : 'E',
        messages: const [],
        photoBytes: trainer?.photoBytes,
        photoUrl: trainer?.photoUrl ?? '',
        createdAt: trainer?.createdAt,
        role: AppUserRole.trainer,
      );
      return u;
    }

    // Sin trainer asignado: fallback al admin (y preferir objeto persistente)
    final admin = UserStore.instance.users
        .where((u) => u.role == AppUserRole.admin)
        .firstOrNull;
    final adminId = admin?.id ?? '';
    if (adminId.isNotEmpty && _chatUserMap.containsKey(adminId)) {
      return _chatUserMap[adminId]!;
    }
    final name = admin?.name ?? 'Coach';
    return _ChatUser(
      id: admin?.id ?? '',
      name: name,
      initial: name.isNotEmpty ? name[0].toUpperCase() : 'C',
      messages: const [],
      photoBytes: admin?.photoBytes,
      photoUrl: admin?.photoUrl ?? '',
      createdAt: admin?.createdAt,
      role: AppUserRole.admin,
    );
  }

  String _conversationId(String a, String b) {
    final ids = [a, b]..sort();
    return '${ids[0]}__${ids[1]}';
  }

  DateTime _msgDate(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is num) return DateTime.fromMillisecondsSinceEpoch(value.toInt());
    return DateTime.now();
  }

  Future<void> _loadConversation(_ChatUser user) async {
    if (user.id.isEmpty) return;
    final convId = _conversationId(_currentUserId, user.id);
    final query = await _db
        .collection('chats')
        .doc(convId)
        .collection('messages')
        .orderBy('createdAt')
        .get();
    if (!mounted) return;
    setState(() {
      user.messages
        ..clear()
        ..addAll(query.docs.map((d) {
          final data = d.data();
          final senderId = (data['senderId'] ?? '').toString();
          final dbIsAdmin = data['isAdmin'] is bool ? data['isAdmin'] as bool : false;
          final isAdmin = dbIsAdmin ||
              (senderId != _currentUserId &&
                  (user.role == AppUserRole.trainer || user.role == AppUserRole.admin));
          return _Message(
            text: (data['text'] ?? '').toString(),
            isAdmin: isAdmin,
            createdAt: _msgDate(data['createdAt']),
          );
        }));
    });
  }

  Future<void> _sendMessage({
    required _ChatUser user,
    required String text,
  }) async {
    if (user.id.isEmpty) return;
    final now = DateTime.now();
    setState(() {
      user.messages.add(_Message(text: text, isAdmin: true, createdAt: now));
    });
    final convId = _conversationId(_currentUserId, user.id);
    final chatRef = _db.collection('chats').doc(convId);
    await chatRef.set({
      'participants': [_currentUserId, user.id],
      'updatedAt': now.millisecondsSinceEpoch,
    }, SetOptions(merge: true));
    await chatRef.collection('messages').add({
      'text': text,
      'isAdmin': _isAdmin || _isTrainer,
      'senderId': _currentUserId,
      'createdAt': now.millisecondsSinceEpoch,
    });
  }

  // Streams en tiempo real por conversación: peerId → subscription
  final Map<String, StreamSubscription<QuerySnapshot>> _convSubs = {};

  // Objetos _ChatUser persistentes (con su unreadCount acumulado)
  final Map<String, _ChatUser> _chatUserMap = {};

  // ── Última vez que se leyó cada conversación (persiste en SharedPreferences)
  static const String _kLastReadPrefix = 'chat_last_read_';

  String _lastReadKey(String convId) => '$_kLastReadPrefix$convId';

  Future<int> _getLastReadTs(String convId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_lastReadKey(convId)) ?? 0;
  }

  /// Lee desde Firestore el timestamp (ms epoch) de `lastReadBy.<uid>` si existe.
  /// Devuelve 0 si no existe o si el usuario no está autenticado.
  Future<int> _readRemoteLastReadMs(String convId) async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return 0;
      final doc = await _db.collection('chats').doc(convId).get();
      final data = doc.data();
      if (data == null) return 0;
      final lastReadBy = data['lastReadBy'];
      if (lastReadBy is Map) {
        final v = lastReadBy[uid];
        if (v is Timestamp) return v.toDate().millisecondsSinceEpoch;
        if (v is num) return v.toInt();
      }
    } catch (e) {
      debugPrint('chat: readRemoteLastRead error: $e');
    }
    return 0;
  }

  Future<void> _markAsRead(String convId) async {
    final prefs = await SharedPreferences.getInstance();
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    await prefs.setInt(_lastReadKey(convId), nowMs);
    // Intento best-effort de escribir la marca remota con serverTimestamp.
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null) {
        await _db.collection('chats').doc(convId).set({
          'lastReadBy': { uid: FieldValue.serverTimestamp() }
        }, SetOptions(merge: true));
      }
    } catch (e) {
      debugPrint('chat: failed to write remote lastRead: $e');
    }
  }

  void _openChat(_ChatUser user) {
    // Ocultar la barra de navegación del shell al abrir conversación
    try {
      shellNavVisibleNotifier.value = false;
    } catch (_) {}
    setState(() {
      user.unreadCount = 0;
      _openedUser = user;
    });
    _syncNotifier();
    // Marcar la conversación como leída ahora
    final convId = _conversationId(_currentUserId, user.id);
    unawaited(_markAsRead(convId));
    unawaited(_loadConversation(user));
  }

  void _closeChat() {
    try {
      shellNavVisibleNotifier.value = true;
    } catch (_) {}
    setState(() => _openedUser = null);
  }

  void _syncNotifier() {
    final total = _chatUserMap.values.fold<int>(0, (s, u) => s + u.unreadCount);
    chatUnreadNotifier.value = total;
  }

  /// Devuelve la lista de chat con los objetos persistentes (con unreadCount real).
  List<_ChatUser> _getChatListForDisplay() {
    return _buildChatList().map((u) => _chatUserMap[u.id] ?? u).toList();
  }

  /// Arranca un stream de escucha para la conversación con [peer].
  /// Primero carga los mensajes no leídos históricos (desde la última lectura),
  /// luego escucha en tiempo real los nuevos.
  void _listenConversation(_ChatUser peer) {
    final peerId = peer.id;
    if (peerId.isEmpty || _convSubs.containsKey(peerId)) return;
    final convId = _conversationId(_currentUserId, peerId);

    // Primero cargamos el histórico no leído
    unawaited(_loadInitialUnread(peer, convId));

    // Luego escuchamos en tiempo real desde ahora
    final startTs = DateTime.now().millisecondsSinceEpoch;
    _convSubs[peerId] = _db
        .collection('chats')
        .doc(convId)
        .collection('messages')
        .where('senderId', isEqualTo: peerId)
        .where('createdAt', isGreaterThan: startTs)
        .snapshots()
        .listen((snap) {
      if (!mounted) return;
      try {
        final addedChanges = snap.docChanges
            .where((c) => c.type == DocumentChangeType.added)
            .toList();
        if (addedChanges.isEmpty) return;
        final newMsgs = <_Message>[];
        for (final c in addedChanges) {
          final data = c.doc.data();
          if (data == null) continue;
          final senderId = (data['senderId'] ?? '').toString();
          final dbIsAdmin = data['isAdmin'] is bool ? data['isAdmin'] as bool : false;
          final isAdmin = dbIsAdmin ||
              (senderId != _currentUserId &&
                  (peer.role == AppUserRole.trainer || peer.role == AppUserRole.admin));
          newMsgs.add(_Message(
            text: (data['text'] ?? '').toString(),
            isAdmin: isAdmin,
            createdAt: _msgDate(data['createdAt']),
          ));
        }

        if (_openedUser?.id == peerId) {
          // Chat abierto → append y marcar como leído
          setState(() {
            peer.messages.addAll(newMsgs);
            peer.unreadCount = 0;
          });
          unawaited(_markAsRead(convId));
        } else {
          // Sumar a los ya no leídos
          setState(() => peer.unreadCount += newMsgs.length);
        }
        _syncNotifier();
      } catch (_) {}
    });
  }

  Future<void> _loadInitialUnread(_ChatUser peer, String convId) async {
    int localLastRead = 0;
    try {
      localLastRead = await _getLastReadTs(convId);
    } catch (_) {}

    int effectiveLastRead = localLastRead;
    try {
      final remoteLastRead = await _readRemoteLastReadMs(convId);
      if (remoteLastRead > effectiveLastRead) {
        effectiveLastRead = remoteLastRead;
        // Actualizar el local para acelerar próximas cargas.
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setInt(_lastReadKey(convId), effectiveLastRead);
        } catch (_) {}
      }
    } catch (_) {}

    // Si effectiveLastRead == 0 contará todos los mensajes.
    try {
      final snap = await _db
          .collection('chats')
          .doc(convId)
          .collection('messages')
          .where('senderId', isEqualTo: peer.id)
          .where('createdAt', isGreaterThan: effectiveLastRead)
          .get();
      if (!mounted) return;
      final count = snap.docs.length;
      if (count > 0) {
        setState(() => peer.unreadCount = count);
        _syncNotifier();
      }
    } catch (_) {}
  }

  void _startAllListeners() {
    if (_isTrainer || _isAdmin) {
      for (final u in _buildChatList()) {
        _chatUserMap[u.id] = u;
        _listenConversation(u);
      }
    }
    if (_isTrainer) {
      _chatUserMap[_adminChatUser.id] = _adminChatUser;
      _listenConversation(_adminChatUser);
    }
    if (_isRegularUser) {
      _chatUserMap[_trainerChatUser.id] = _trainerChatUser;
      _listenConversation(_trainerChatUser);
    }
  }

  @override
  void initState() {
    super.initState();
    _syncNotifier();
    if (_isRegularUser) {
      // Si el usuario normal entra, ocultar la barra (vista de conversación única)
      try {
        shellNavVisibleNotifier.value = false;
      } catch (_) {}
      unawaited(_loadConversation(_trainerChatUser));
      // El usuario siempre ve su chat abierto → marcar como leído al entrar
      if (_trainerChatUser.id.isNotEmpty) {
        final convId = _conversationId(_currentUserId, _trainerChatUser.id);
        unawaited(_markAsRead(convId));
      }
      // Si no hay trainer ni admin en memoria, intentar recuperar admin desde Firestore
      if (_trainerChatUser.id.isEmpty) {
        unawaited(_ensureAdminForOrphanUser());
      }
    }
    // Arranca todos los listeners de mensajes en tiempo real
    _startAllListeners();
    // Si el trainer/admin no se cargó todavía, reintenta cuando UserStore actualice
    UserStore.instance.addListener(_retryListenersIfNeeded);
  }

  Future<void> _ensureAdminForOrphanUser() async {
    try {
      final me = UserStore.instance.currentUser;
      final trainerId = (me.trainerId ?? '').trim();
      if (trainerId.isNotEmpty) return;

      // Preferir admin ya cargado en UserStore
      final admins = UserStore.instance.users.where((u) => u.role == AppUserRole.admin).toList();
      if (admins.isNotEmpty) {
        final chatUser = _toChatUser(admins.first);
        if (!mounted) return;
        setState(() {
          _chatUserMap[chatUser.id] = chatUser;
        });
        _listenConversation(chatUser);
        unawaited(_loadConversation(chatUser));
        final convId = _conversationId(_currentUserId, chatUser.id);
        unawaited(_markAsRead(convId));
        return;
      }

      // No hay admin en memoria: buscar en Firestore
      final q = await _db
          .collection('users')
          .where('role', isEqualTo: appUserRoleToString(AppUserRole.admin))
          .limit(1)
          .get();
      if (q.docs.isEmpty) return;
      final d = q.docs.first;
      final data = d.data();
      final name = data['name'] is String ? data['name'] as String : 'Admin';
      final chatUser = _ChatUser(
        id: d.id,
        name: name,
        initial: name.isNotEmpty ? name[0].toUpperCase() : 'A',
        messages: const [],
        photoBytes: null,
        photoUrl: data['photoUrl'] is String ? data['photoUrl'] as String : '',
        role: AppUserRole.admin,
        createdAt: null,
      );
      if (!mounted) return;
      setState(() {
        _chatUserMap[chatUser.id] = chatUser;
      });
      _listenConversation(chatUser);
      unawaited(_loadConversation(chatUser));
      final convId = _conversationId(_currentUserId, chatUser.id);
      unawaited(_markAsRead(convId));
    } catch (_) {}
  }

  /// Cuando UserStore carga los datos (trainer, admin), arranca los listeners
  /// que no se pudieron iniciar porque el id del interlocutor era vacío.
  void _retryListenersIfNeeded() {
    if (!mounted) return;
    // Caso usuario regular: reintentar cuando se cargue el trainerId
    if (_isRegularUser && _convSubs.isEmpty) {
      final rebuilt = _buildTrainerChatUser();
      if (rebuilt.id.isNotEmpty) {
        UserStore.instance.removeListener(_retryListenersIfNeeded);
        _chatUserMap[rebuilt.id] = rebuilt;
        _listenConversation(rebuilt);
        unawaited(_loadConversation(rebuilt));
      }
    }

    // Caso trainer/admin: si al inicio no había usuarios cargados, reintentar
    // cuando UserStore actualice la lista de usuarios.
    if ((_isTrainer || _isAdmin) && _convSubs.isEmpty) {
      final list = _buildChatList();
      if (list.isNotEmpty) {
        UserStore.instance.removeListener(_retryListenersIfNeeded);
        for (final u in list) {
          // Registrar en el mapa y arrancar listener si aún no existe
          _chatUserMap[u.id] = u;
          _listenConversation(u);
          unawaited(_loadConversation(u));
        }
        // Asegurar que el chat con admin esté también escuchado para trainers
        if (_isTrainer && _adminChatUser.id.isNotEmpty) {
          _chatUserMap[_adminChatUser.id] = _adminChatUser;
          _listenConversation(_adminChatUser);
          unawaited(_loadConversation(_adminChatUser));
        }
      } else {
        // Si aún no hay usuarios en UserStore, intentar forzar carga desde Firestore.
        unawaited(UserStore.instance.loadAllUsersFromFirestore().then((_) {
          if (!mounted) return;
          final rebuiltList = _buildChatList();
          if (rebuiltList.isNotEmpty) {
            UserStore.instance.removeListener(_retryListenersIfNeeded);
            for (final u in rebuiltList) {
              _chatUserMap[u.id] = u;
              _listenConversation(u);
              unawaited(_loadConversation(u));
            }
          }
        }));
      }
    }
  }

  @override
  void dispose() {
    // Restaurar visibilidad de la barra al salir
    try {
      shellNavVisibleNotifier.value = true;
    } catch (_) {}
    UserStore.instance.removeListener(_retryListenersIfNeeded);
    for (final sub in _convSubs.values) {
      sub.cancel();
    }
    _convSubs.clear();
    _chatUserMap.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: UserStore.instance,
      builder: (context, _) {
        // ── USUARIO / Sin clave: mostrar vista similar a trainer.
        // - `user`: mostrar la tarjeta de su entrenador (si vinculada).
        // - `sinclave`: no mostrar tarjetas; solo FAB de contacto con admin.
        if (_isRegularUser) {
          final list = _getChatListForDisplay();
          return Stack(
            children: [
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                child: _openedUser == null
                    ? _UserListView(
                        key: const ValueKey('user-list'),
                        users: list,
                        onUserTap: _openChat,
                      )
                    : _ConversationView(
                        key: ValueKey(_openedUser!.id),
                        user: _openedUser!,
                        onBack: _closeChat,
                        onMessageSent: (text) {
                          final opened = _openedUser;
                          if (opened == null) return;
                          unawaited(_sendMessage(user: opened, text: text));
                        },
                      ),
              ),
              // Para usuarios sin clave mostrar FAB de contacto al admin
              if (_openedUser == null && _role == AppUserRole.sinclave)
                Positioned(
                  right: 18,
                  bottom: 18,
                  child: _AdminContactButton(
                    adminName: _adminChatUser.name,
                    unreadCount: _adminChatUser.unreadCount,
                    onTap: () => _openChat(_adminChatUser),
                  ),
                ),
            ],
          );
        }

        // ── TRAINER: lista de sus usuarios + botón "Admin" abajo ──
        if (_isTrainer) {
          final list = _getChatListForDisplay();
          return Stack(
            children: [
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                child: _openedUser == null
                    ? _UserListView(
                        key: const ValueKey('trainer-list'),
                        users: list,
                        onUserTap: _openChat,
                      )
                    : _ConversationView(
                        key: ValueKey(_openedUser!.id),
                        user: _openedUser!,
                        onBack: _closeChat,
                        onMessageSent: (text) {
                          final opened = _openedUser;
                          if (opened == null) return;
                          unawaited(_sendMessage(user: opened, text: text));
                        },
                      ),
              ),
              // Botón "Hablar con Admin" en esquina inferior derecha
              if (_openedUser == null)
                Positioned(
                  right: 18,
                  bottom: 18,
                  child: _AdminContactButton(
                    adminName: _adminChatUser.name,
                    unreadCount: _adminChatUser.unreadCount,
                    onTap: () => _openChat(_adminChatUser),
                  ),
                ),
            ],
          );
        }

        // ── ADMIN: lista de todos ──
        final list = _getChatListForDisplay();
        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          child: _openedUser == null
              ? _UserListView(
                  key: const ValueKey('admin-list'),
                  users: list,
                  onUserTap: _openChat,
                  isAdmin: true,
                  currentAdminId: _currentUserId,
                )
              : _ConversationView(
                  key: ValueKey(_openedUser!.id),
                  user: _openedUser!,
                  onBack: _closeChat,
                  onMessageSent: (text) {
                    final opened = _openedUser;
                    if (opened == null) return;
                    unawaited(_sendMessage(user: opened, text: text));
                  },
                ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Admin contact button (for trainers)
// ---------------------------------------------------------------------------

class _AdminContactButton extends StatelessWidget {
  const _AdminContactButton({
    required this.adminName,
    required this.onTap,
    this.unreadCount = 0,
  });

  final String adminName;
  final VoidCallback onTap;
  final int unreadCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        FloatingActionButton.extended(
          onPressed: onTap,
          backgroundColor: theme.colorScheme.primary,
          foregroundColor: Colors.black,
          icon: const Icon(Icons.admin_panel_settings_rounded),
          label: Text('Chat con $adminName'),
        ),
        if (unreadCount > 0)
          Positioned(
            top: -6,
            right: -6,
            child: Container(
              padding: const EdgeInsets.all(4),
              constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
              decoration: const BoxDecoration(
                color: Colors.red,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Text(
                unreadCount > 9 ? '9+' : '$unreadCount',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// User list
// ---------------------------------------------------------------------------

enum _ChatAdminFilter { all, myUsers, trainers, noCode }

class _UserListView extends StatefulWidget {
  const _UserListView({
    super.key,
    required this.users,
    required this.onUserTap,
    this.isAdmin = false,
    this.currentAdminId = '',
  });

  final List<_ChatUser> users;
  final void Function(_ChatUser) onUserTap;
  final bool isAdmin;
  final String currentAdminId;

  @override
  State<_UserListView> createState() => _UserListViewState();
}

class _UserListViewState extends State<_UserListView> {
  final TextEditingController _searchCtrl = TextEditingController();
  String _searchQuery = '';
  _ChatAdminFilter _filter = _ChatAdminFilter.all;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  // Filtro y diálogos se manejan inline; métodos auxiliares eliminados

  


  List<_ChatUser> _filteredUsers() {
    var list = widget.users.toList();
    if (widget.isAdmin && _filter != _ChatAdminFilter.all) {
      list = list.where((u) {
        return switch (_filter) {
          _ChatAdminFilter.trainers => u.role == AppUserRole.trainer,
          _ChatAdminFilter.myUsers =>
            u.role == AppUserRole.user &&
                u.trainerId == widget.currentAdminId,
          _ChatAdminFilter.noCode =>
            (u.role == AppUserRole.sinclave) ||
            (u.role == AppUserRole.user &&
                (u.trainerId == null || u.trainerId!.trim().isEmpty)),
          _ChatAdminFilter.all => true,
        };
      }).toList();
    }
    if (_searchQuery.trim().isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      list = list.where((u) => u.name.toLowerCase().contains(q)).toList();
    }

    // Si el usuario es admin y el filtro está en 'Todos', mostrar primero
    // los usuarios sin clave (sin trainerId) para facilitar contacto.
    if (widget.isAdmin && _filter == _ChatAdminFilter.all) {
      list.sort((a, b) {
        final aNoTrainer = a.role == AppUserRole.sinclave || (a.role == AppUserRole.user && (a.trainerId == null || a.trainerId!.trim().isEmpty));
        final bNoTrainer = b.role == AppUserRole.sinclave || (b.role == AppUserRole.user && (b.trainerId == null || b.trainerId!.trim().isEmpty));
        if (aNoTrainer && !bNoTrainer) return -1;
        if (!aNoTrainer && bNoTrainer) return 1;
        // Si ambos son 'Sin clave', ordenamos por createdAt (más recientes primero)
        if (aNoTrainer && bNoTrainer) {
          final aDate = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          final bDate = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          final cmp = bDate.compareTo(aDate);
          if (cmp != 0) return cmp;
        }
        // Fallback: ordenar por nombre
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final visible = _filteredUsers();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Chats',
          style: theme.textTheme.titleLarge?.copyWith(
            color: theme.colorScheme.onSurface,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _searchCtrl,
          style: TextStyle(color: theme.colorScheme.onSurface),
          onChanged: (v) => setState(() => _searchQuery = v),
          decoration: InputDecoration(
            hintText: 'Buscar...',
            hintStyle: TextStyle(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
              fontSize: 14,
            ),
            prefixIcon: Icon(
              Icons.search_rounded,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.62),
            ),
            suffixIcon: _searchQuery.isNotEmpty
                ? IconButton(
                    onPressed: () {
                      _searchCtrl.clear();
                      setState(() => _searchQuery = '');
                    },
                    icon: Icon(
                      Icons.close_rounded,
                      color:
                          theme.colorScheme.onSurface.withValues(alpha: 0.62),
                    ),
                  )
                : null,
            filled: true,
            fillColor: theme.cardColor,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(24),
              borderSide: BorderSide(
                color: AppTheme.surfaceBorderFor(context),
                width: theme.brightness == Brightness.light ? 1.25 : 1,
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(24),
              borderSide: BorderSide(
                color: AppTheme.surfaceBorderFor(context),
                width: theme.brightness == Brightness.light ? 1.25 : 1,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(24),
              borderSide: BorderSide(color: theme.colorScheme.primary),
            ),
          ),
        ),
        if (widget.isAdmin) ...[  
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _ChatFilterChip(
                  label: 'Todos',
                  selected: _filter == _ChatAdminFilter.all,
                  glass: true,
                  onTap: () => setState(() => _filter = _ChatAdminFilter.all),
                ),
                const SizedBox(width: 8),
                _ChatFilterChip(
                  label: 'Entrenadores',
                  selected: _filter == _ChatAdminFilter.trainers,
                  glass: true,
                  onTap: () => setState(() => _filter = _ChatAdminFilter.trainers),
                ),
                const SizedBox(width: 8),
                _ChatFilterChip(
                  label: 'Mis usuarios',
                  selected: _filter == _ChatAdminFilter.myUsers,
                  glass: true,
                  onTap: () => setState(() => _filter = _ChatAdminFilter.myUsers),
                ),
                const SizedBox(width: 8),
                _ChatFilterChip(
                  label: 'Sin clave',
                  selected: _filter == _ChatAdminFilter.noCode,
                  glass: true,
                  onTap: () => setState(() => _filter = _ChatAdminFilter.noCode),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 14),
        if (visible.isEmpty)
          Text(
            'Aún no hay chats.',
            style: TextStyle(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.62),
            ),
          )
        else
          ...visible.map(
            (u) => _UserEntry(user: u, onTap: () => widget.onUserTap(u)),
          ),
      ],
    );
  }
}

class _ChatFilterChip extends StatelessWidget {
  const _ChatFilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.glass = false,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool glass;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (glass) {
      final isDark = theme.brightness == Brightness.dark;
      final baseColor = isDark
          ? Colors.black.withValues(alpha: 0.30)
          : Colors.white.withValues(alpha: 0.20);
      final borderColor = isDark
          ? Colors.white.withValues(alpha: 0.10)
          : Colors.white.withValues(alpha: 0.40);
      return ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: GestureDetector(
            onTap: onTap,
            child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                    decoration: BoxDecoration(
                      color: baseColor,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: borderColor, width: 0.8),
                    ),
                    child: Text(
                      label,
                      style: TextStyle(
                        color: selected ? theme.colorScheme.primary : theme.colorScheme.onSurface,
                        fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                        fontSize: 13,
                      ),
                    ),
                  ),
          ),
        ),
      );
    }

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? theme.colorScheme.primary : theme.cardColor,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected
                ? theme.colorScheme.primary
                : AppTheme.surfaceBorderFor(context),
            width:
                selected
                    ? 0
                    : (theme.brightness == Brightness.light ? 1.2 : 1),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.black : theme.colorScheme.onSurface,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            fontSize: 13,
          ),
        ),
      ),
    );
  }
}

class _UserEntry extends StatelessWidget {
  const _UserEntry({required this.user, required this.onTap});

  final _ChatUser user;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isLight = theme.brightness == Brightness.light;
    final bool isSinClave = user.role == AppUserRole.sinclave ||
      (user.role == AppUserRole.user &&
        (user.trainerId == null || user.trainerId!.trim().isEmpty));
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        decoration: BoxDecoration(
          color: theme.cardColor,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSinClave ? theme.colorScheme.primary : AppTheme.surfaceBorderFor(context),
            width: isLight ? 1.35 : 1,
          ),
          boxShadow: AppTheme.surfaceShadowFor(
            context,
            alpha: 0.09,
            blurRadius: 12,
            offsetY: 3,
            addTopHighlight: true,
          ),
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(14),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  // Avatar con badge de no leídos
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      _Avatar(
                        initial: user.initial,
                        photoBytes: user.photoBytes,
                        photoUrl: user.photoUrl,
                      ),
                      if (user.unreadCount > 0)
                        Positioned(
                          top: -3,
                          right: -3,
                          child: Container(
                            width: 16,
                            height: 16,
                            decoration: const BoxDecoration(
                              color: Colors.red,
                              shape: BoxShape.circle,
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              user.unreadCount > 9
                                  ? '9+'
                                  : '${user.unreadCount}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      if (isSinClave)
                        Positioned(
                          top: -3,
                          left: -3,
                          child: Container(
                            width: 18,
                            height: 18,
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primary,
                              shape: BoxShape.circle,
                              border: Border.all(color: theme.cardColor, width: 2),
                            ),
                            child: Icon(
                              Icons.vpn_key_rounded,
                              size: 11,
                              color: Colors.black,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          user.name,
                          style: TextStyle(
                            color: theme.colorScheme.onSurface,
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                          ),
                        ),
                        if (isSinClave) ...[
                          const SizedBox(height: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primary.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: theme.colorScheme.primary.withValues(alpha: 0.18)),
                            ),
                            child: Text(
                              'Sin clave',
                              style: TextStyle(
                                color: theme.colorScheme.primary,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                        // Ocultar preview del último mensaje (no mostrar texto aquí)
                      ],
                    ),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.62),
                    size: 20,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Conversation view
// ---------------------------------------------------------------------------

class _ConversationView extends StatefulWidget {
  const _ConversationView({
    super.key,
    required this.user,
    this.onBack,
    this.titleOverride,
    this.coachNameForMessages,
    this.showCoachNameInMessages = false,
    this.coachPhotoBytes,
    this.coachPhotoUrl,
    required this.onMessageSent,
  });

  final _ChatUser user;
  final VoidCallback? onBack;
  final String? titleOverride;
  final String? coachNameForMessages;
  final bool showCoachNameInMessages;
  final Uint8List? coachPhotoBytes;
  final String? coachPhotoUrl;
  final void Function(String text) onMessageSent;

  @override
  State<_ConversationView> createState() => _ConversationViewState();
}

class _ConversationViewState extends State<_ConversationView> {
  final TextEditingController _inputCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();
  final FocusNode _inputFocus = FocusNode();
  int _lastMessagesCount = 0;

  @override
  void initState() {
    super.initState();
    _inputCtrl.addListener(() => setState(() {}));
    _inputFocus.addListener(() => setState(() {}));
    _lastMessagesCount = widget.user.messages.length;
  }

  @override
  void didUpdateWidget(covariant _ConversationView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final prev = _lastMessagesCount;
    final now = widget.user.messages.length;
    if (now > prev) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
    }
    _lastMessagesCount = now;
  }

  @override
  void dispose() {
    _inputFocus.dispose();
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _send() {
    final text = _inputCtrl.text.trim();
    if (text.isEmpty) return;
    widget.onMessageSent(text);
    _inputCtrl.clear();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
  }

  void _scrollToBottom() {
    if (_scrollCtrl.hasClients) {
      _scrollCtrl.animateTo(
        _scrollCtrl.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final canGoBack = widget.onBack != null;
    final theme = Theme.of(context);
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final showPreview = bottomInset > 0 && _inputFocus.hasFocus;

    return Stack(
      fit: StackFit.expand,
      children: [
        Column(
          children: [
            // ── Header (glassmorphism) ──
            ClipRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                  decoration: BoxDecoration(
                    color: theme.brightness == Brightness.dark
                        ? Colors.black.withValues(alpha: 0.28)
                        : Colors.white.withValues(alpha: 0.12),
                    border: Border(
                      bottom: BorderSide(
                        color: theme.brightness == Brightness.dark
                            ? Colors.white.withValues(alpha: 0.10)
                            : Colors.white.withValues(alpha: 0.18),
                        width: 0.8,
                      ),
                    ),
                  ),
                  child: Row(
                    children: [
                      if (canGoBack)
                        IconButton(
                          onPressed: widget.onBack,
                          icon: Icon(
                            Icons.arrow_back_ios_new_rounded,
                            color: Theme.of(context).colorScheme.primary,
                            size: 20,
                          ),
                          tooltip: 'Atrás',
                        )
                      else
                        const SizedBox(width: 10),
                      _Avatar(
                        initial: widget.user.initial,
                        size: 36,
                        photoBytes: widget.user.photoBytes,
                        photoUrl: widget.user.photoUrl,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          widget.titleOverride ?? widget.user.name,
                          style: TextStyle(
                            color: theme.brightness == Brightness.dark
                                ? Colors.white.withValues(alpha: 0.95)
                                : Colors.black.withValues(alpha: 0.9),
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            // ── Messages ──
            Expanded(
              child: ListView.builder(
                controller: _scrollCtrl,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                itemCount: widget.user.messages.length,
                itemBuilder: (context, index) {
                  final msg = widget.user.messages[index];
                    final senderName = widget.showCoachNameInMessages && msg.isAdmin
                      ? widget.coachNameForMessages
                      : null;
                    final senderPhotoBytes = widget.showCoachNameInMessages && msg.isAdmin
                      ? widget.coachPhotoBytes
                      : null;
                    final senderPhotoUrl = widget.showCoachNameInMessages && msg.isAdmin
                      ? widget.coachPhotoUrl
                      : null;
                    return _MessageBubble(
                    message: msg,
                    senderName: senderName,
                    senderPhotoBytes: senderPhotoBytes,
                    senderPhotoUrl: senderPhotoUrl,
                    );
                },
              ),
            ),
            // ── Input ──
            _InputBar(controller: _inputCtrl, onSend: _send, focusNode: _inputFocus),
          ],
        ),

        // Preview encima del teclado cuando se abre y el campo está enfocado
        if (showPreview)
          Positioned(
            left: 16,
            right: 16,
            bottom: bottomInset + 8,
            child: KeyboardInputPreview(
              text: _inputCtrl.text,
              visible: showPreview,
              onTap: () => FocusScope.of(context).requestFocus(_inputFocus),
            ),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Message bubble
// ---------------------------------------------------------------------------

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.message,
    this.senderName,
    this.senderPhotoBytes,
    this.senderPhotoUrl,
  });

  final _Message message;
  final String? senderName;
  final Uint8List? senderPhotoBytes;
  final String? senderPhotoUrl;

  @override
  Widget build(BuildContext context) {
    final isAdmin = message.isAdmin;
    final theme = Theme.of(context);
    return Align(
      alignment: isAdmin ? Alignment.centerRight : Alignment.centerLeft,
      child: Column(
        crossAxisAlignment: isAdmin
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [
          if (senderName != null && senderName!.trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 4, left: 2, right: 2),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: isAdmin ? MainAxisAlignment.end : MainAxisAlignment.start,
                children: [
                  if (!isAdmin) ...[
                    _buildSmallAvatar(context, senderName!, senderPhotoBytes, senderPhotoUrl),
                    const SizedBox(width: 6),
                  ],
                  Text(
                    senderName!,
                    style: TextStyle(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.62),
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (isAdmin) ...[
                    const SizedBox(width: 6),
                    _buildSmallAvatar(context, senderName!, senderPhotoBytes, senderPhotoUrl),
                  ],
                ],
              ),
            ),
          Container(
            margin: EdgeInsets.only(bottom: 8),
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.72,
            ),
            padding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: isAdmin
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurface.withValues(alpha: 0.09),
              border: isAdmin
                  ? null
                  : Border.all(
                      color: AppTheme.surfaceBorderFor(context),
                      width: theme.brightness == Brightness.light ? 1.1 : 1,
                    ),
              boxShadow: isAdmin
                  ? null
                  : AppTheme.surfaceShadowFor(
                      context,
                      alpha: 0.06,
                      blurRadius: 8,
                      offsetY: 2,
                    ),
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(16),
                topRight: const Radius.circular(16),
                bottomLeft: Radius.circular(isAdmin ? 16 : 4),
                bottomRight: Radius.circular(isAdmin ? 4 : 16),
              ),
            ),
            child: Text(
              message.text,
              style: TextStyle(
                color: isAdmin ? Colors.black : theme.colorScheme.onSurface,
                fontSize: 14,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }

    Widget _buildSmallAvatar(BuildContext context, String name, Uint8List? bytes, String? url) {
      final theme = Theme.of(context);
      final initial = name.trim().isNotEmpty ? name.trim()[0].toUpperCase() : '?';
      return Container(
        width: 20,
        height: 20,
        decoration: BoxDecoration(
          color: theme.colorScheme.primary,
          shape: BoxShape.circle,
          border: theme.brightness == Brightness.light
              ? Border.all(color: AppTheme.surfaceBorderFor(context), width: 1.0)
              : null,
        ),
        clipBehavior: Clip.antiAlias,
        alignment: Alignment.center,
        child: bytes != null
            ? Image.memory(bytes, fit: BoxFit.cover, width: 20, height: 20)
            : (url != null && url.isNotEmpty)
                ? Image.network(
                    url,
                    fit: BoxFit.cover,
                    width: 20,
                    height: 20,
                    errorBuilder: (_, _, _) => Text(
                      initial,
                      style: TextStyle(color: Colors.black, fontSize: 10, fontWeight: FontWeight.w700),
                    ),
                  )
                : Text(
                    initial,
                    style: TextStyle(color: Colors.black, fontSize: 10, fontWeight: FontWeight.w700),
                  ),
      );
    }
}

// ---------------------------------------------------------------------------
// Input bar
// ---------------------------------------------------------------------------

class _InputBar extends StatelessWidget {
  const _InputBar({required this.controller, required this.onSend, this.focusNode});

  final TextEditingController controller;
  final VoidCallback onSend;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isLight = theme.brightness == Brightness.light;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return AnimatedPadding(
      duration: const Duration(milliseconds: 160),
      padding: EdgeInsets.only(bottom: bottomInset),
      curve: Curves.easeOut,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          border: Border(
            top: BorderSide(
              color: AppTheme.surfaceBorderFor(context),
              width: isLight ? 1.2 : 1,
            ),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                focusNode: focusNode,
                controller: controller,
                style: TextStyle(
                  color: theme.colorScheme.onSurface,
                  fontSize: 14,
                ),
                onSubmitted: (_) => onSend(),
                decoration: InputDecoration(
                  hintText: 'Escribe un mensaje...',
                  hintStyle: TextStyle(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.62),
                  ),
                  filled: true,
                  fillColor: theme.cardColor,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide(
                      color: AppTheme.surfaceBorderFor(context),
                      width: isLight ? 1.2 : 1,
                    ),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide(
                      color: AppTheme.surfaceBorderFor(context),
                      width: isLight ? 1.2 : 1,
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide(color: theme.colorScheme.primary),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            GestureDetector(
              onTap: onSend,
              child: Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.send_rounded,
                  color: Colors.black,
                  size: 20,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Avatar
// ---------------------------------------------------------------------------

class _Avatar extends StatelessWidget {
  const _Avatar({
    required this.initial,
    this.size = 42,
    this.photoBytes,
    this.photoUrl = '',
  });

  final String initial;
  final double size;
  final Uint8List? photoBytes;
  final String photoUrl;

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary,
        shape: BoxShape.circle,
        border: isLight
            ? Border.all(color: AppTheme.surfaceBorderFor(context), width: 1.0)
            : null,
      ),
      clipBehavior: Clip.antiAlias,
      alignment: Alignment.center,
      child: photoBytes != null
          ? Image.memory(
              photoBytes!,
              fit: BoxFit.cover,
              width: size,
              height: size,
            )
          : photoUrl.isNotEmpty
              ? Image.network(
                  photoUrl,
                  fit: BoxFit.cover,
                  width: size,
                  height: size,
                  errorBuilder: (_, _, _) => Text(
                    initial,
                    style: TextStyle(
                      color: Colors.black,
                      fontWeight: FontWeight.w700,
                      fontSize: size * 0.4,
                    ),
                  ),
                )
              : Text(
                  initial,
                  style: TextStyle(
                    color: Colors.black,
                    fontWeight: FontWeight.w700,
                    fontSize: size * 0.4,
                  ),
                ),
    );
  }
}
