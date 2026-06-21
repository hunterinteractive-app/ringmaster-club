// lib/services/clubs/club_session.dart

import 'package:flutter/foundation.dart';

import '../../models/clubs/club_summary.dart';
import 'club_service.dart';

class ClubSession extends ChangeNotifier {
  ClubSession({ClubService? service})
      : _service = service ?? ClubService();

  final ClubService _service;

  List<ClubSummary> _clubs = const [];
  ClubSummary? _activeClub;
  bool _isLoading = false;
  String? _errorMessage;

  List<ClubSummary> get clubs => List.unmodifiable(_clubs);

  ClubSummary? get activeClub => _activeClub;

  bool get isLoading => _isLoading;

  String? get errorMessage => _errorMessage;

  bool get hasClubs => _clubs.isNotEmpty;

  bool get hasMultipleClubs => _clubs.length > 1;

  bool get canManageActiveClub => _activeClub?.canManageClub ?? false;

  bool get isActiveClubOwner => _activeClub?.isOwner ?? false;

  Future<void> loadClubs({String? preferredClubId}) async {
    if (_isLoading) {
      return;
    }

    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final loadedClubs = await _service.getMyClubs();
      _clubs = List.unmodifiable(loadedClubs);

      if (_clubs.isEmpty) {
        _activeClub = null;
        return;
      }

      final normalizedPreferredClubId = preferredClubId?.trim();

      if (normalizedPreferredClubId != null &&
          normalizedPreferredClubId.isNotEmpty) {
        _activeClub = _findClubById(normalizedPreferredClubId);
      }

      _activeClub ??= _findMatchingCurrentClub();
      _activeClub ??= _clubs.first;
    } catch (error) {
      _clubs = const [];
      _activeClub = null;
      _errorMessage = _friendlyError(error);
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void setActiveClub(ClubSummary club) {
    final matchingClub = _findClubById(club.clubId);

    if (matchingClub == null) {
      throw ArgumentError.value(
        club.clubId,
        'club.clubId',
        'The club is not available in the current club session.',
      );
    }

    if (_activeClub == matchingClub) {
      return;
    }

    _activeClub = matchingClub;
    _errorMessage = null;
    notifyListeners();
  }

  bool setActiveClubById(String clubId) {
    final normalizedClubId = clubId.trim();
    if (normalizedClubId.isEmpty) {
      return false;
    }

    final club = _findClubById(normalizedClubId);
    if (club == null) {
      return false;
    }

    setActiveClub(club);
    return true;
  }

  Future<void> refresh() async {
    await loadClubs(preferredClubId: _activeClub?.clubId);
  }

  Future<bool> hasPermission(String permissionKey) async {
    final club = _activeClub;
    final normalizedPermissionKey = permissionKey.trim();

    if (club == null || normalizedPermissionKey.isEmpty) {
      return false;
    }

    if (club.isOwner) {
      return true;
    }

    return _service.hasPermission(
      clubId: club.clubId,
      permissionKey: normalizedPermissionKey,
    );
  }

  void clear() {
    _clubs = const [];
    _activeClub = null;
    _isLoading = false;
    _errorMessage = null;
    notifyListeners();
  }

  ClubSummary? _findClubById(String clubId) {
    for (final club in _clubs) {
      if (club.clubId == clubId) {
        return club;
      }
    }

    return null;
  }

  ClubSummary? _findMatchingCurrentClub() {
    final currentClub = _activeClub;
    if (currentClub == null) {
      return null;
    }

    return _findClubById(currentClub.clubId);
  }

  String _friendlyError(Object error) {
    final message = error.toString().trim();

    if (message.isEmpty) {
      return 'Unable to load your clubs.';
    }

    return 'Unable to load your clubs: $message';
  }
}