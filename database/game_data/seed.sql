-- ============================================================
-- 共生之缚 Symbiont —— 游戏内容库初始数据（M0 占位，M1 起按 GDD 扩充）
-- 注: 所有 JSON 列必须是合法 JSON 字符串。
-- ============================================================

-- ---------- 物品 ----------
INSERT INTO items (id, name, type, desc, icon, stats, obtain, flags) VALUES
  ('iron_sword',   '铁剑',     'weapon',   '地牢守尸人留下的制式铁剑。', '', '{"atk": 10}', 'map_pickup', '{}'),
  ('wood_shield',  '木盾',     'shield',   '能格挡正面攻击的木盾。',       '', '{"def": 3}',  'map_pickup', '{}'),
  ('grappling_hook','钩锁',    'upgrade',  '可抓取金属锚点的钩锁，大幅扩展移动范围。', '', '{}', 'map_pickup', '{"movement": "hookshot"}'),
  ('steam_boots',  '蒸汽靴',   'upgrade',  '工程师的蒸汽动力靴，跳跃可二段。', '', '{}', 'faction_engineer', '{"movement": "double_jump", "faction": "engineer"}'),
  ('tainted_leg',  '污化之腿', 'upgrade',  '献祭改造的腿部，长按可大跳。', '', '{}', 'sacrifice', '{"movement": "big_jump", "faction": "heretic"}'),
  ('monster_limb', '怪物肢体', 'quest',    '沾染邪神气息的怪物残肢，可献祭。', '', '{}', 'enemy_drop', '{}');

-- ---------- 敌人 ----------
INSERT INTO enemies (id, name, hp, speed, behavior, attack_damage, drops, desc) VALUES
  ('patrol_slime',  '巡逻史莱姆', 8,  40, 'patrol', 1, '{"sacrifice_part": "monster_limb"}', '第一层最常见的敌人，直线巡逻。'),
  ('spore_shooter', '孢子射手',   6,  20, 'ranged', 1, '{"sacrifice_part": "monster_limb"}', '远程吐孢子弹，近距离无力。'),
  ('dive_fly',      '俯冲飞虫',   5,  120, 'dive',   1, '{"sacrifice_part": "monster_limb"}', '空中巡游，发现玩家后俯冲。'),
  ('gatekeeper_boss','守门 Boss', 24,  60, 'boss',   2, '{"soul": 50}', '第三层把守出路，结局结算的关键；上一任走到这里的容器。');

-- ---------- NPC ----------
INSERT INTO npc (id, name, faction, location, desc) VALUES
  ('heretic_priest',  '异教徒祭司', 'heretic',  '第二层东侧祭坛', '提供献祭路线：腿部改造与手臂攻击。'),
  ('engineer_master', '工程师',     'engineer', '第二层西侧工坊', '提供探索路线：蒸汽靴二段跳与武器升级。'),
  ('watchman',        '守钟人',     '',         '第一层钟厅',     '上一批失败的容器，割断钟绳后被锁在钟下；重复给钟厅机关提示。');

-- ---------- 对话 ----------
INSERT INTO dialogues (id, npc_id, title, lines, next_id, branch) VALUES
  ('intro_parasite_1', '', '寄生体的低语',
   '[{"speaker": "寄生体", "text": "醒了？血还在流……嘘，我是唯一还听得见的声音。"}, {"speaker": "寄生体", "text": "去猎杀那些爬行的怪物，把它们的肢体带到我面前。"}, {"speaker": "寄生体", "text": "献给我。我保你活下去——只要你肯给。"}]',
   'intro_parasite_2', ''),
  ('intro_parasite_2', '', '新生指导',
   '[{"speaker": "寄生体", "text": "去吧，我的容器。我在祭坛边等你带回来的馈赠。"}]',
   '', ''),
  ('refuse_die', '', '拒绝',
   '[{"speaker": "寄生体", "text": "你拒绝了。那就慢慢看着自己散掉——剩下的，我收下。"}]',
   '', 'ending:refuse_die'),
  ('heretic_offer', 'heretic_priest', '异教徒的提议',
   '[{"speaker": "祭司", "text": "成为我们的一员，接受神的赐福。你的肢体将化作武器。"}]',
   '', ''),
  ('engineer_offer', 'engineer_master', '工程师的提议',
   '[{"speaker": "工程师", "text": "别听那帮疯子。帮我修好蒸汽机，我给你蒸汽靴和更好的剑。"}]',
   '', '');

-- ---------- 对话 · 第一层 锈钟回廊（M2 剧情） ----------
-- 结构：进入时播 floor1_enter；钟厅 floor1_bell；祭坛 floor1_altar；
-- 扩建段断桥 floor1_bridge、遗物廊 floor1_relic；层门 floor1_gate。
INSERT INTO dialogues (id, npc_id, title, lines, next_id, branch) VALUES
  ('floor1_enter', '', '锈钟回廊',
   '[{"speaker": "寄生体", "text": "往下，一直往下。钟早就停了，可你听——还有东西在敲。"}, {"speaker": "寄生体", "text": "这里死过很多人。他们的骨头还热着，够你走很远。"}]',
   '', ''),
  ('floor1_bell', '', '断绳',
   '[{"speaker": "寄生体", "text": "那口钟是异教徒挂上去的。钟声能压住下面的东西，可惜绳子断了。"}, {"speaker": "寄生体", "text": "听见了吗？钟底下有东西在啃同类的骨头。"}, {"speaker": "寄生体", "text": "钟绳不是自己断的。有人从上面割断了它。"}]',
   '', ''),
  ('floor1_altar', '', '第二座祭坛',
   '[{"speaker": "寄生体", "text": "又一座祭坛。把手伸进去，我给你新的力量。"}, {"speaker": "寄生体", "text": "别怕疼。疼是活着的人才有的东西。"}]',
   '', ''),
  ('floor1_bridge', '', '断桥',
   '[{"speaker": "寄生体", "text": "桥是给朝圣者走的。钟响之前，这里每天有人排队。"}, {"speaker": "寄生体", "text": "后来他们发现，走到桥中央的人不会再回来。"}, {"speaker": "寄生体", "text": "你看桥板下面的抓痕——它们是从下面往上抓的。"}]',
   '', ''),
  ('floor1_relic', '', '遗物廊',
   '[{"speaker": "寄生体", "text": "这些龛里放的不是死人。是还没死透的容器。"}, {"speaker": "寄生体", "text": "教会把失败的祭品摆在这里，等它们自己长回去。"}, {"speaker": "寄生体", "text": "别碰石棺。里面的东西认得你的味道。"}]',
   '', ''),
  ('floor1_gate', '', '通往上一层',
   '[{"speaker": "寄生体", "text": "上去就是第二层。别急着走——先把这里吃干净。"}, {"speaker": "寄生体", "text": "你越强，我越像你。"}]',
   '', ''),
  ('floor1_watchman', 'watchman', '守钟人',
   '[{"speaker": "守钟人", "text": "别碰那根绳子。钟一响，下面的东西就知道有人来了。"}, {"speaker": "守钟人", "text": "我割断过它一次。后来他们把我锁在钟下，让我听它空响。"}, {"speaker": "守钟人", "text": "你要过去，就拉绳。骨门只认钟声，不认人。"}]',
   '', ''),
  ('floor1_watchman_after', 'watchman', '钟响之后',
   '[{"speaker": "守钟人", "text": "听见了吗？它在钟肚子里翻身。"}, {"speaker": "守钟人", "text": "骨门开了。你欠下面的东西一笔债，记得还。"}]',
   '', ''),
  ('floor1_bell_ring', '', '锈钟',
   '[{"speaker": "寄生体", "text": "好孩子。再响一点，让它记住你的味道。"}]',
   '', ''),
  ('sacrifice_after_1', '', '第一道馈赠',
   '[{"speaker": "寄生体", "text": "第一口。你的脊背里现在多了一根不属于你的东西。"}, {"speaker": "寄生体", "text": "别怕，它比你更懂怎么活下去。"}]',
   '', ''),
  ('sacrifice_after_2', '', '第二道馈赠',
   '[{"speaker": "寄生体", "text": "第二道。它已经学会用你的眼睛看路了。"}, {"speaker": "寄生体", "text": "再喂下去，你就分不清是谁在走路。"}]',
   '', '');

-- ---------- 对话 · 第二层 铸炉与圣坛（M3 剧情） ----------
-- 两个 NPC 各有一套 offer（第一次听）/ confirm（第二次按 K 确认）/ after（选完再聊）。
-- 选择结果由 floor2.gd 写 GameManager.faction，台词不写死在代码里。
INSERT INTO dialogues (id, npc_id, title, lines, next_id, branch) VALUES
  ('floor2_enter', '', '铸炉与圣坛',
   '[{"speaker": "寄生体", "text": "上面有人在烧炉子，也有人点着骨头。两边都觉得自己在救你。"}, {"speaker": "寄生体", "text": "别急着信。先听他们把话说完，再决定把哪条腿交出去。"}]',
   '', ''),
  ('floor2_engineer_offer', 'engineer_master', '工程师的提议',
   '[{"speaker": "工程师", "text": "站住。你从下面爬上来的？那口钟响的时候，整座工坊都在震。"}, {"speaker": "工程师", "text": "我修了一辈子蒸汽机，现在只差一个人帮我压住第三根管子。"}, {"speaker": "工程师", "text": "帮我，我给你一双蒸汽靴。跳得一样高，可你能在半空中再借一次力。"}]',
   '', ''),
  ('floor2_engineer_confirm', 'engineer_master', '把命押在蒸汽上',
   '[{"speaker": "工程师", "text": "想清楚了？靴子一旦上脚，就再也拆不下来。"}, {"speaker": "工程师", "text": "行。记住：蒸汽只认活人。你死了，它就把你当废铁吐出来。"}]',
   '', ''),
  ('floor2_engineer_after', 'engineer_master', '工坊里的规矩',
   '[{"speaker": "工程师", "text": "别把炉门关死。留一条缝，压力才有地方去。"}, {"speaker": "工程师", "text": "上面那扇门后是守门的东西。它不怕火，也不怕蒸汽。"}]',
   '', ''),
  ('floor2_heretic_offer', 'heretic_priest', '祭司的提议',
   '[{"speaker": "祭司", "text": "孩子，你身上有神的味道。不是香水，是血里长出来的那种。"}, {"speaker": "祭司", "text": "工程师给你铁，我给你肉。铁会锈，肉会记得怎么长回来。"}, {"speaker": "祭司", "text": "让我把你的腿接上神性。跳得一样高，可你会听见落地时骨头在唱歌。"}]',
   '', ''),
  ('floor2_heretic_confirm', 'heretic_priest', '把命押在骨头上',
   '[{"speaker": "祭司", "text": "别怕。第一刀下去会疼，第二刀开始就是恩典。"}, {"speaker": "祭司", "text": "你的腿会先学会走路，再学会自己找路。到那时，你最好还认得自己。"}]',
   '', ''),
  ('floor2_heretic_after', 'heretic_priest', '圣坛上的规矩',
   '[{"speaker": "祭司", "text": "神不说话。祂只在你献上东西时，轻轻动一下。"}, {"speaker": "祭司", "text": "上面的人把门守得很紧。他们怕的不是你，是你身后那位。"}]',
   '', ''),
  ('floor2_gate', '', '封印门之后',
   '[{"speaker": "寄生体", "text": "第二层到头了。门上的齿轮和骨环都亮了，只认你选的那一边。"}, {"speaker": "寄生体", "text": "再往上就是守门的东西。它闻得出你身上有几个人。"}]',
   '', '');

-- ---------- 对话 · 第三层 守门者之厅（M3 剧情） ----------
-- 守门者是上一任容器；Boss 死后的低语把“你也是容器”挑明。
INSERT INTO dialogues (id, npc_id, title, lines, next_id, branch) VALUES
  ('floor3_enter', '', '守门者之厅',
   '[{"speaker": "寄生体", "text": "别出声。它在这里守了很久，久到忘了自己原来也是人。"}, {"speaker": "寄生体", "text": "门就在它背后。想出去，就得先让它躺下。"}]',
   '', ''),
  ('floor3_boss_intro', 'gatekeeper_boss', '上一任容器',
   '[{"speaker": "守门者", "text": "又来了一个。你身上有它的味道，比我当年还重。"}, {"speaker": "守门者", "text": "我数过。走到这里的每一个人，都以为自己能出去。"}, {"speaker": "守门者", "text": "门归我守。你要过去，就把我剩下的这点东西也拿走吧。"}]',
   '', ''),
  ('floor3_after_boss', '', '门开了',
   '[{"speaker": "寄生体", "text": "看，它倒下了。和你一样，都是被喂出来的东西。"}, {"speaker": "寄生体", "text": "现在门开了。你身上带走了多少，门外的人就会看见多少。"}]',
   '', ''),
  ('true_he_return', '', '回到起点',
   '[{"speaker": "寄生体", "text": "你真的回来了。旧货梯还能动，说明这地方也记得你。"}, {"speaker": "寄生体", "text": "上一次你在这里献出第一块骨头。手从那天起就没干净过。"}, {"speaker": "寄生体", "text": "石碗还在。把留下的那块放回去，别交给我。"}]',
   '', ''),
  ('true_he_relic_pickup', '', '第一块骨头',
   '[{"speaker": "寄生体", "text": "一块发白的旧骨片，没被消化干净——留好，回去要用。"}, {"speaker": "寄生体", "text": "那是你第一次献出去的东西。拿回祭坛，放回碗里。这一次，别求它收下。"}]',
   '', '');

-- ---------- 结局 ----------
INSERT INTO endings (id, name, condition, weight, desc) VALUES
  ('refuse_die',   '拒绝献祭（死）', '新手教程中选择拒绝献祭', 1, '隐藏结局：宁死不屈，游戏结束。'),
  ('human',        '人类结局',      '击败守门 Boss 且献祭次数 == 1', 5, '守住人性，凭自己的意志走出地牢。'),
  ('transformed',  '异化结局',      '击败守门 Boss 且献祭次数 > 1', 5, '察觉自身异化，或自毁，或沦为新的守门 Boss。'),
  ('true_he',      '真结局 HE',     '击败守门 Boss 后回到起点取得特殊道具并完成反噬', 3, '清除异化状态，反咬邪神。');

-- ---------- 献祭改造 ----------
INSERT INTO sacrifices (id, part, route, desc, effect) VALUES
  ('arm_claw',  'arm', 'heretic', '手臂改造：以肢体为武器，超高攻低防。', '{"attack_mode": "arm_claw"}'),
  ('leg_taint', 'leg', 'heretic', '腿部改造：长按跳跃为大跳（与蒸汽靴跳高相同）。', '{"jump": "big_jump"}');
