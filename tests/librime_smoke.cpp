#include <rime_api.h>
#include <dlfcn.h>
#include <iostream>
#include <string>
#include <stdexcept>
RimeApi* a;RimeSessionId s;int n=0;
void check(bool ok,std::string msg){if(!ok)throw std::runtime_error(msg);++n;}
std::string drain(){RIME_STRUCT(RimeCommit,c);if(!a->get_commit(s,&c))return "";std::string t=c.text;a->free_commit(&c);return t;}
std::string key(int k,int mask=0){a->process_key(s,k,mask);return drain();}
std::string type(const std::string&raw){std::string t;for(unsigned char k:raw)t+=key(k);return t;}
void clear(){a->clear_composition(s);drain();}
void option(const char*name,bool b){clear();a->set_option(s,name,b);}
std::string top(std::string*comment=nullptr){RIME_STRUCT(RimeContext,c);check(a->get_context(s,&c),"no context");check(c.menu.num_candidates>0,"empty menu");std::string t=c.menu.candidates[0].text;if(comment)*comment=c.menu.candidates[0].comment?c.menu.candidates[0].comment:"";a->free_context(&c);return t;}
int page(){RIME_STRUCT(RimeContext,c);a->get_context(s,&c);int p=c.menu.page_no;a->free_context(&c);return p;}
int main(int argc,char**argv){try{check(argc==2,"userdir needed");check(dlopen("/usr/lib/rime-plugins/librime-lua.so",RTLD_NOW|RTLD_GLOBAL),"plugin failed");a=rime_get_api();RIME_STRUCT(RimeTraits,t);t.user_data_dir=argv[1];t.shared_data_dir="/usr/share/rime-data";t.app_name="rime.tiger-features";t.distribution_code_name="fcitx5-rime";t.distribution_version="5.1.23";t.log_dir=argv[1];t.min_log_level=2;const char*mods[]={"default","lua",nullptr};t.modules=mods;a->setup(&t);a->initialize(&t);s=a->create_session();check(s&&a->select_schema(s,"tiger_sentence"),"schema failed");a->set_option(s,"ascii_mode",false);
 check(a->get_option(s,"tiger_sentence_correction_weak"),"weak preference lost");check(a->get_option(s,"tiger_sentence_early_commit"),"early commit preference lost");
 std::string c;check(type("`nihc").empty(),"lookup auto committed");check(top(&c)=="你好"&&c.find("jx bh")!=std::string::npos&&c.find("女子")!=std::string::npos,"automatic reverse split/comment wrong");check(key(' ')=="你好","lookup commit wrong");
 clear();type("`nihc");check(page()==0,"reverse initial page");check(key('n',4).empty(),"reverse Ctrl+n committed");check(page()==1,"reverse Ctrl+n paging");check(key('p',4).empty(),"reverse Ctrl+p committed");check(page()==0,"reverse Ctrl+p paging");
 clear();type("jxbh");key(0xff09);key(0xff09,1);check(top()=="你好","Tab backwards changed first text");check(key(' ')=="你好","Shift+Tab backwards commit failed");
 clear();check(type(";")=="；","single semicolon should commit immediately");check(std::string(a->get_input(s)).empty(),"semicolon left pending input");
 clear();check(type("\\")=="、","single backslash should commit dunhao");
 clear();check(type("jxbh ;")=="你好；","sentence plus semicolon failed");
 clear();check(type("jxbh\\")=="你好、","sentence plus dunhao failed");
 clear();check(type("jxbh;").empty()&&std::string(a->get_input(s))=="jxbh;","native semicolon rank suffix changed");
 clear();type("/sx");check(page()==0,"symbols initial page");key('n',4);check(page()==1,"Ctrl+n paging");key('p',4);check(page()==0,"Ctrl+p paging");
 option("tiger_sentence_correction_off",true);option("tiger_sentence_early_commit",false);type("lomn");key(0xff09);check(type("ueottu").empty(),"Tab unexpectedly committed");check(top()=="草码的是我","Tab lock lost");check(key(' ')=="草码的是我","Tab commit lost");
 option("tiger_sentence_correction_weak",true);option("tiger_sentence_early_commit",true);check(type("ptue").empty(),"correction empty-code commit regression");check(top(&c)=="是的"&&c=="🐞","correction candidate wrong");check(key(' ')=="是的","correction commit wrong");
 clear();type("jxbh");check(top(&c)=="你好"&&c.empty(),"normal typing gained split");
 RIME_STRUCT(RimeContext,nc);a->get_context(s,&nc);bool normal_emoji=false;for(int i=0;i<nc.menu.num_candidates;i++){if(std::string(nc.menu.candidates[i].text)=="👋")normal_emoji=true;}a->free_context(&nc);check(normal_emoji,"normal emoji missing");
 clear();type("`ni");check(top(&c)=="你"&&c.find("亻")!=std::string::npos,"automatic single character split missing");
 clear();type("`nihc");check(top(&c)=="你好"&&c.find("jx bh")!=std::string::npos&&c.find("女子")!=std::string::npos,"automatic reverse split missing");std::cout<<"split "<<c<<"\n";
 clear();type("`nihc");check(top()=="你好","emoji changed initial text");RimeCandidateListIterator it{};check(a->candidate_list_begin(s,&it),"candidate iterator failed");bool found=false;int idx=-1;std::string et;while(a->candidate_list_next(&it)){if(it.index<5)std::cout<<"emoji candidate "<<it.index<<" "<<it.candidate.text<<"\n";if(std::string(it.candidate.text)=="👋"){found=true;idx=it.index;et=it.candidate.text;}}a->candidate_list_end(&it);check(found,"emoji missing");check(a->select_candidate(s,idx),"emoji select");check(drain()==et,"emoji selection not submitted");
 clear();type("`nihc");check(a->highlight_candidate(s,idx),"emoji highlight failed");check(key(' ')=="👋","emoji space");
 clear();type("`nihc");check(a->highlight_candidate(s,idx),"emoji highlight failed");{auto submitted=key('u');std::cout<<"continued: commit=["<<submitted<<"] input=["<<a->get_input(s)<<"]\n";check(submitted=="👋"&&std::string(a->get_input(s))=="u","emoji selection lost on continued typing");}
 clear();type("`nihc");check(a->highlight_candidate(s,idx),"emoji highlight failed");check(key('.')=="👋。","emoji punctuation confirmation");
 clear();
 clear();type("jxbh");key(0xff09);check(key(' ')=="👋","normal emoji Tab+space failed");
 clear();type("jxbh");key(0xff09);check(key('u')=="👋"&&std::string(a->get_input(s))=="u","normal emoji continued typing failed");
 clear();type("jxbh");key(0xff09);check(key('.')=="👋。","normal emoji punctuation failed");
 clear();type("/tjql");clear();std::string submitted=type("awmenamcuntaueottuawmenamcuntaueottu");submitted+=key(' ');check(submitted=="买椟还珠的是我买椟还珠的是我","normal early commit text changed");clear();type("/tj");std::string report=top();check(report.find("字数:14")!=std::string::npos,"statistics missed/duplicated early commits");std::cout<<report<<"\n";
 clear();option("tiger_sentence_correction_weak",true);option("tiger_sentence_early_commit",true);a->destroy_session(s);a->finalize();std::cout<<"PASS "<<n<<" checks\n";
 }catch(const std::exception&e){std::cerr<<"FAIL "<<e.what()<<"\n";return 1;}}
