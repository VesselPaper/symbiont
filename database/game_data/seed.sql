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
  ('gatekeeper_boss','守门 Boss', 120, 60, 'boss',   3, '{"soul": 50}', '第三层把守出路，结局结算的关键。');

-- ---------- NPC ----------
INSERT INTO npc (id, name, faction, location, desc) VALUES
  ('heretic_priest',  '异教徒祭司', 'heretic',  '第二层东侧祭坛', '提供献祭路线：腿部改造与手臂攻击。'),
  ('engineer_master', '工程师',     'engineer', '第二层西侧工坊', '提供探索路线：蒸汽靴二段跳与武器升级。');

-- ---------- 对话 ----------
INSERT INTO dialogues (id, npc_id, title, lines, next_id, branch) VALUES
  ('intro_parasite_1', '', '寄生体的低语',
   '[{"speaker": "寄生体", "text": "你醒了。奄奄一息，血流不止……"}, {"speaker": "寄生体", "text": "献祭吧。把眼前这具怪物的肢体献给我，我保你活下去。"}]',
   'intro_parasite_2', ''),
  ('intro_parasite_2', '', '新生指导',
   '[{"speaker": "寄生体", "text": "很好。力量在涌上来，不是么？"}, {"speaker": "系统", "text": "按 J 攻击，按 K 交互。"}]',
   '', ''),
  ('refuse_die', '', '拒绝',
   '[{"speaker": "系统", "text": "你拒绝了献祭。生命一点点流逝……黑暗吞没了你。"}]',
   '', 'ending:refuse_die'),
  ('heretic_offer', 'heretic_priest', '异教徒的提议',
   '[{"speaker": "祭司", "text": "成为我们的一员，接受神的赐福。你的肢体将化作武器。"}]',
   '', ''),
  ('engineer_offer', 'engineer_master', '工程师的提议',
   '[{"speaker": "工程师", "text": "别听那帮疯子。帮我修好蒸汽机，我给你蒸汽靴和更好的剑。"}]',
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
