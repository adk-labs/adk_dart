class Skill {
  Skill({
    required this.name,
    required this.description,
    this.version = '0.1.0',
  });

  final String name;
  final String description;
  final String version;
}

class SkillRegistry {
  final Map<String, Skill> _skills = <String, Skill>{};

  void register(Skill skill) {
    _skills[skill.name] = skill;
  }

  Skill? get(String name) => _skills[name];

  List<Skill> list() => _skills.values.toList(growable: false);
}
