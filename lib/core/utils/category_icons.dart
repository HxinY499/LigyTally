import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

const categoryIcons = <String, IconData>{
  'restaurant': FLucideIcons.utensils,
  'travel': FLucideIcons.plane,
  'beauty': FLucideIcons.sparkles,
  'transport': FLucideIcons.bus,
  'shopping': FLucideIcons.shoppingBag,
  'home': FLucideIcons.home,
  'fun': FLucideIcons.gamepad2,
  'medical': FLucideIcons.stethoscope,
  'medicine': FLucideIcons.pill,
  'clinic': FLucideIcons.hospital,
  'pet': FLucideIcons.pawPrint,
  'pet_food': FLucideIcons.cookie,
  'red_packet': FLucideIcons.gift,
  'gift': FLucideIcons.gift,
  'delivery': FLucideIcons.truck,
  'sport': FLucideIcons.dumbbell,
  'repayment': FLucideIcons.creditCard,
  'digital': FLucideIcons.smartphone,
  'network': FLucideIcons.wifi,
  'study': FLucideIcons.graduationCap,
  'course': FLucideIcons.presentation,
  'book': FLucideIcons.bookOpen,
  'haircut': FLucideIcons.scissors,
  'clothes': FLucideIcons.shirt,
  'baby': FLucideIcons.baby,
  'membership': FLucideIcons.badgeCheck,
  'parents': FLucideIcons.heart,
  'utilities': FLucideIcons.building,
  'rent': FLucideIcons.key,
  'family': FLucideIcons.users,
  'favor': FLucideIcons.handHeart,
  'meal': FLucideIcons.utensils,
  'vegetable': FLucideIcons.shoppingBasket,
  'fine_dining': FLucideIcons.wine,
  'drink': FLucideIcons.coffee,
  'water': FLucideIcons.droplet,
  'fruit': FLucideIcons.apple,
  'snack': FLucideIcons.croissant,
  'bus': FLucideIcons.bus,
  'subway': FLucideIcons.trainTrack,
  'taxi': FLucideIcons.carTaxiFront,
  'bike': FLucideIcons.bike,
  'train': FLucideIcons.train,
  'flight': FLucideIcons.plane,
  'car': FLucideIcons.car,
  'game': FLucideIcons.gamepad2,
  'movie': FLucideIcons.film,
  'puzzle': FLucideIcons.puzzle,
  'toy_car': FLucideIcons.car,
  'water_bill': FLucideIcons.droplet,
  'property': FLucideIcons.building2,
  'electricity': FLucideIcons.zap,
  'gas': FLucideIcons.flame,
  'heating': FLucideIcons.thermometer,
  'fish': FLucideIcons.fish,
  'salary': FLucideIcons.banknote,
  'bonus': FLucideIcons.gift,
  'part_time': FLucideIcons.briefcase,
  'finance': FLucideIcons.trendingUp,
  'living_expense': FLucideIcons.wallet,
  'allowance': FLucideIcons.heartHandshake,
  'family_income': FLucideIcons.usersRound,
  'refund': FLucideIcons.undo2,
  'other': FLucideIcons.ellipsis,
};

IconData categoryIcon(String key) => categoryIcons[key] ?? FLucideIcons.receipt;

/// 图标选择器里可供挑选的 key（按主题分组、去掉图形重复项）。
///
/// [categoryIcons] 是「历史 key → 图标」的映射表，里面有一批同图不同名的
/// 别名（`meal` 与 `restaurant` 都是餐具、`travel` 与 `flight` 都是飞机）。
/// 直接把它的 keys 铺进选择网格，用户会看到十几对一模一样的格子，
/// 完全没法选。所以选择器用这份**人工去重**的清单，
/// 顺序也按「吃穿行住 → 娱乐健康 → 人情教育 → 收入理财」排，
/// 让人扫一眼就能定位，而不是在无序的图标海里找。
const categoryIconChoices = <String>[
  // 吃
  'restaurant', 'fine_dining', 'drink', 'snack', 'fruit', 'vegetable', 'water',
  'delivery',
  // 穿 / 买
  'shopping', 'clothes', 'haircut', 'beauty', 'digital', 'membership',
  // 行
  'transport', 'subway', 'taxi', 'bike', 'train', 'flight', 'car',
  // 住
  'home', 'rent', 'utilities', 'electricity', 'gas', 'heating', 'network',
  'property',
  // 娱乐 / 健康
  'fun', 'movie', 'puzzle', 'sport', 'medical', 'medicine', 'clinic',
  // 人情 / 教育 / 家庭
  'gift', 'favor', 'parents', 'family', 'baby', 'study', 'course', 'book',
  'pet', 'pet_food', 'fish',
  // 收入 / 理财
  'salary', 'part_time', 'finance', 'living_expense', 'allowance',
  'family_income', 'refund', 'repayment',
  // 兜底
  'other',
];
