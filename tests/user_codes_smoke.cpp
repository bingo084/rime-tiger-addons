// Reuse the real-librime session and keystroke helpers.
#define main addon_smoke_main
#include "librime_smoke.cpp"
#undef main

int main(int argc, char** argv) {
 try {
  check(argc == 3, "userdir and before/after mode needed");
  bool after = std::string(argv[2]) == "after";
  check(dlopen("/usr/lib/rime-plugins/librime-lua.so", RTLD_NOW|RTLD_GLOBAL), "plugin failed");
  a = rime_get_api();
  RIME_STRUCT(RimeTraits, t);
  t.user_data_dir = argv[1]; t.shared_data_dir = "/usr/share/rime-data";
  t.app_name = "rime.tiger-user-codes"; t.log_dir = argv[1]; t.min_log_level = 2;
  const char* mods[] = {"default", "lua", nullptr}; t.modules = mods;
  a->setup(&t); a->initialize(&t); s = a->create_session();
  check(s && a->select_schema(s, "tiger_sentence"), "schema failed");
  a->set_option(s, "ascii_mode", false);
  option("tiger_sentence_correction_off", true);
  option("tiger_sentence_early_commit", false);
  const std::pair<std::string, std::string> cases[] = {
   {"vcv", "要不要"}, {"cv", after ? "尾" : "不要"}, {"vc", after ? "肢" : "要不"},
   {"cv;", after ? "不要" : "尾"}, {"vc;", after ? "要不" : "肢"},
   {"jxvcv", "你要不要"}, {after ? "cv;sh" : "cvsh", "不要说"},
   {after ? "vc;sh" : "vcsh", "要不说"}, {"vcvueottu", "要不要的是我"},
   {"jxbh", "你好"}, {"cbvb", "不要"}, {"vbcb", "要不"},
  };
  for (const auto& test : cases) {
   clear(); check(type(test.first).empty(), "unexpected early commit: " + test.first);
   check(top() == test.second, "first candidate: " + test.first + " -> " + top());
   check(key(' ') == test.second, "commit wrong: " + test.first);
  }
  for (const auto& test : {std::pair<std::string, std::string>{"cv", after ? "尾" : "不要"},
                         {"vc", after ? "肢" : "要不"}, {"vcv", "要不要"}}) {
   clear(); check(type(test.first + "/") == test.second + "、", "slash captured after personal code");
   check(std::string(a->get_input(s)).empty(), "slash left input");
  }
  clear(); type("cv"); key(0xff09);
  check(key(' ') == (after ? "不要" : "尾"), "Tab did not select second candidate");
  clear(); type("vc"); key(0xff09);
  check(key(' ') == (after ? "要不" : "肢"), "Tab did not select original/new candidate");
  clear(); type("`nihc"); std::string comment;
  check(top(&comment) == "你好" && comment.find("女子") != std::string::npos, "reverse/split changed");
  check(key(' ') == "你好", "reverse commit wrong");
  option("tiger_sentence_early_commit", true);
  const auto& test = cases[6];
  clear(); std::string submitted = type(test.first); submitted += key(' ');
  check(submitted == test.second, "personal sentence with early commit failed: " + submitted);
  a->destroy_session(s); a->finalize();
  std::cout << "PASS personal words " << argv[2] << ": " << n << " checks\n";
 } catch (const std::exception& e) { std::cerr << "FAIL " << e.what() << "\n"; return 1; }
}
