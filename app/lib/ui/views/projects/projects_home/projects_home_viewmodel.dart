import 'package:stacked/stacked.dart';

import 'package:app_box/app/app.locator.dart';
import 'package:app_box/services/projects_service.dart';

enum ProjectsHomeState { empty, list, loading }

class ProjectsHomeViewModel extends BaseViewModel {
  final _projects = locator<ProjectsService>();
  ProjectsHomeState _state = ProjectsHomeState.loading;

  ProjectsHomeState get state => _state;
  List<AppBoxProject> get projects => _projects.all;

  Future<void> load() async {
    _state = ProjectsHomeState.loading;
    notifyListeners();
    await Future.delayed(const Duration(milliseconds: 200));
    _state = _projects.all.isEmpty ? ProjectsHomeState.empty : ProjectsHomeState.list;
    notifyListeners();
  }
}
