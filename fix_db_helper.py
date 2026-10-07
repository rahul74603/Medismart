with open('lib/db_helper.dart', 'r', encoding='utf-8') as f:
    lines = f.readlines()

with open('lib/db_helper.dart', 'w', encoding='utf-8') as f:
    f.writelines(lines[:472])
    f.write('\n  // --- BILLS ALIAS ---\n')
    f.write('  static Future<List<Map<String, dynamic>>> getBills() async => await getAllBills();\n')
    f.write('}\n')

print("File fixed successfully!")
    lines = f.readlines()

with open('lib/db_helper.dart', 'w', encoding='utf-8') as f:
    f.writelines(lines[:472])
    f.write('\n  // --- BILLS ALIAS ---\n')
    f.write('  static Future<List<Map<String, dynamic>>> getBills() async => await getAllBills();\n')
    f.write('}\n')

print("File fixed successfully!")

