import 'package:app_box/app/app.locator.dart';
import 'package:app_box/services/gate_service.dart';

/// A project flowing through the app_box pipeline.
class AppBoxProject {
  final String id;
  final String name;
  final String? brand;
  final List<String> targets;
  AppBoxProject({required this.id, required this.name, this.brand, this.targets = const []});
}

/// 8.7 — the projects facade. Re-applies the Repository → Facade → ViewModel
/// skeleton the kit exemplar demonstrated, now for app_box’s own domain.
/// (The skeleton is the point of this base; the exemplar’s domain was only an example.)
///
/// In-memory for now; the repository swap seam (seed/supabase/appwrite) from
/// stacked_kit_data is where a real backend plugs in with no viewmodel change.
class ProjectsService {
  final _projects = <AppBoxProject>[];

  List<AppBoxProject> get all => List.unmodifiable(_projects);

  AppBoxProject create({required String name, String? brand, List<String> targets = const []}) {
    final p = AppBoxProject(
      id: DateTime.now().microsecondsSinceEpoch.toRadixString(36),
      name: name,
      brand: brand,
      targets: targets,
    );
    _projects.add(p);
    // Declaring the ship triple up front (targets chosen here are what every
    // later gate reads — brief J2). Gate 3 confirms this exact triple.
    locator<GateService>().declaredShipTriple = null;
    return p;
  }
}
