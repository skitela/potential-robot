#ifndef MB_TEACHER_MODE_RESOLVER_INCLUDED
#define MB_TEACHER_MODE_RESOLVER_INCLUDED

enum MbTeacherMode
  {
   MB_TEACHER_MODE_GLOBAL_ONLY = 0,
   MB_TEACHER_MODE_GLOBAL_PLUS_PERSONAL = 1,
   MB_TEACHER_MODE_PERSONAL_PRIMARY = 2
  };

MbTeacherMode MbResolveTeacherMode(const MbTeacherPackageContract &contract)
  {
   string mode = contract.teacher_mode;
   StringToUpper(mode);
   if(mode == "PERSONAL_PRIMARY")
      return MB_TEACHER_MODE_PERSONAL_PRIMARY;
   if(mode == "GLOBAL_PLUS_PERSONAL")
      return MB_TEACHER_MODE_GLOBAL_PLUS_PERSONAL;
   return MB_TEACHER_MODE_GLOBAL_ONLY;
  }

bool MbTeacherAllowsPersonal(const MbTeacherPackageContract &contract)
  {
   MbTeacherMode mode = MbResolveTeacherMode(contract);
   return contract.personal_allowed || mode == MB_TEACHER_MODE_GLOBAL_PLUS_PERSONAL || mode == MB_TEACHER_MODE_PERSONAL_PRIMARY;
  }

string MbTeacherModeLabel(const MbTeacherPackageContract &contract)
  {
   MbTeacherMode mode = MbResolveTeacherMode(contract);
   if(mode == MB_TEACHER_MODE_PERSONAL_PRIMARY)
      return "PERSONAL_PRIMARY";
   if(mode == MB_TEACHER_MODE_GLOBAL_PLUS_PERSONAL)
      return "GLOBAL_PLUS_PERSONAL";
   return "GLOBAL_ONLY";
  }

#endif
