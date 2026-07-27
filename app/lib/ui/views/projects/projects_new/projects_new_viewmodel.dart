import 'package:stacked/stacked.dart';

import 'package:app_box/app/app.locator.dart';
import 'package:app_box/services/projects_service.dart';

enum ProjectsNewState { form, validating, error }

class ProjectsNewViewModel extends BaseViewModel {
  final _projects = locator<ProjectsService>();
  ProjectsNewState _state = ProjectsNewState.form;
  String _name = '';
  String _brand = '';
  String? _formError;

  ProjectsNewState get state => _state;
  String? get formError => _formError;

  void onName(String v) => _name = v;
  void onBrand(String v) => _brand = v;

  Future<void> create() async {
    _state = ProjectsNewState.validating;
    _formError = null;
    notifyListeners();
    await Future.delayed(const Duration(milliseconds: 150));
    if (_name.trim().isEmpty) {
      _state = ProjectsNewState.error;
      _formError = 'A project name is required.';
      notifyListeners();
      return;
    }
    _projects.create(name: _name.trim(), brand: _brand.trim().isEmpty ? null : _brand.trim());
    _state = ProjectsNewState.form;
    notifyListeners();
  }
}
