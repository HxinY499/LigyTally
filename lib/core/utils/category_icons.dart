import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

/// key → 图标 的映射表。
///
/// **这张表只能加，不能删也不能改指向。** key 是以字符串形式存进数据库
/// （`categories.icon_key`）并写进导出的分类配置 JSON 的，删掉或重指
/// 等于悄悄改掉用户已有分类的图标，甚至让老备份恢复后一片兜底图标。
/// 所以表里留着一批同图别名（`meal` 与 `restaurant` 都是餐具、
/// `travel` 与 `flight` 都是飞机），它们是历史，不是设计。
///
/// 界面上「可挑选哪些图标」不看这张表，看 [categoryIconGroups]。
const categoryIcons = <String, IconData>{
  // ── 历史 key（内置分类种子与旧版备份都在用，勿动）──────────────
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

  // ── 为「用户自建分类」补的图标 ──────────────────────────────
  //
  // 上面那批是为内置的 44 个默认分类配的，只覆盖了内置分类恰好用到的图形。
  // 但选择器要服务的是用户**自己想建什么**，两者需求不同：以前想建
  // 「加油 / 停车 / 洗车」只能三个都选 car，想建「话费 / 保险 / 税 / 投资」
  // 干脆无图可选。下面按记账里高频出现、且 lucide 有明确对应图形的分类补齐。
  //
  // 吃喝
  'takeout': FLucideIcons.handPlatter,
  'beer': FLucideIcons.beer,
  'milk_tea': FLucideIcons.cupSoda,
  'milk': FLucideIcons.milk,
  'candy': FLucideIcons.candy,
  'cake': FLucideIcons.cakeSlice,
  'ice_cream': FLucideIcons.iceCream,
  'popcorn': FLucideIcons.popcorn,
  // 购物
  'supermarket': FLucideIcons.shoppingCart,
  'store': FLucideIcons.store,
  'shoes': FLucideIcons.footprints,
  'bag': FLucideIcons.backpack,
  'glasses': FLucideIcons.glasses,
  'watch': FLucideIcons.watch,
  'jewelry': FLucideIcons.gem,
  'laptop': FLucideIcons.laptop,
  'household': FLucideIcons.package,
  // 交通
  'fuel': FLucideIcons.fuel,
  'parking': FLucideIcons.circleParking,
  'toll': FLucideIcons.road,
  'ship': FLucideIcons.ship,
  // 居住
  'phone_bill': FLucideIcons.signal,
  'furniture': FLucideIcons.sofa,
  'appliance': FLucideIcons.washingMachine,
  'fridge': FLucideIcons.refrigerator,
  'tv': FLucideIcons.tv,
  'lamp': FLucideIcons.lamp,
  'cleaning': FLucideIcons.sprayCan,
  'renovation': FLucideIcons.hammer,
  'tools': FLucideIcons.wrench,
  // 娱乐
  'music': FLucideIcons.music,
  'theater': FLucideIcons.drama,
  'swim': FLucideIcons.waves,
  'ball': FLucideIcons.volleyball,
  'trip': FLucideIcons.luggage,
  'hotel': FLucideIcons.hotel,
  'ticket': FLucideIcons.ticket,
  'camera': FLucideIcons.camera,
  'art': FLucideIcons.palette,
  'camping': FLucideIcons.tent,
  'party': FLucideIcons.partyPopper,
  'toy': FLucideIcons.toyBrick,
  // 健康
  'injection': FLucideIcons.syringe,
  'bandage': FLucideIcons.bandage,
  'checkup': FLucideIcons.heartPulse,
  'insurance': FLucideIcons.shieldCheck,
  // 教育 / 家人 / 宠物
  'library': FLucideIcons.library,
  'stationery': FLucideIcons.notebookPen,
  'language': FLucideIcons.languages,
  'dog': FLucideIcons.dog,
  'cat': FLucideIcons.cat,
  'flower': FLucideIcons.flower,
  'plant': FLucideIcons.leaf,
  // 收入 / 金融
  'savings': FLucideIcons.piggyBank,
  'coins': FLucideIcons.coins,
  'transfer': FLucideIcons.arrowLeftRight,
  'tax': FLucideIcons.landmark,
  'invoice': FLucideIcons.receipt,
  'subscription': FLucideIcons.repeat,
  'discount': FLucideIcons.percent,
  // 杂项
  'umbrella': FLucideIcons.umbrella,
  'idea': FLucideIcons.lightbulb,
  'recycle': FLucideIcons.recycle,
};

IconData categoryIcon(String key) => categoryIcons[key] ?? FLucideIcons.receipt;

/// ── 自定义图片图标 ─────────────────────────────────────────
///
/// 用户上传的图片也存在 `categories.icon_key` 这一列里，形如
/// `custom:<uuid>`。**不新开一列**，是因为：
///
/// - 全应用有近十处读 `iconKey` 渲染图标，多一列意味着每处都要多传一个字段，
///   还得保证两列不会写歪（有路径但 key 还是 'other' 之类）；
/// - `icon_key` 已经在备份 JSON、分类配置 JSON 里跑了三个版本，
///   在既有字段上加前缀是唯一不需要改表结构、老包也能原样读的做法。
///
/// 前缀选 `custom:` 而非纯 uuid：内置 key 全是 `[a-z_]`，冒号在其中不可能
/// 出现，两者天然不会撞。反过来，老版本读到 `custom:xxx` 会走
/// [categoryIcon] 的兜底分支显示 receipt —— 降级而非崩溃。
const categoryCustomIconPrefix = 'custom:';

bool isCustomCategoryIcon(String key) =>
    key.startsWith(categoryCustomIconPrefix);

/// 从 iconKey 里取出图片 id；不是自定义图标则返回 null。
String? customCategoryIconId(String key) {
  if (!isCustomCategoryIcon(key)) return null;
  final id = key.substring(categoryCustomIconPrefix.length);
  return id.isEmpty ? null : id;
}

/// 由图片 id 拼出 iconKey。
String customCategoryIconKey(String iconId) =>
    '$categoryCustomIconPrefix$iconId';

/// id 是否合法。
///
/// 只允许 uuid 用到的字符：这个 id 会直接拼进文件名和备份包内路径，
/// 放行 `/` 或 `..` 等于给导入的备份留了一条路径穿越的口子。
bool isValidCustomIconId(String id) =>
    id.isNotEmpty &&
    id.length <= 64 &&
    RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(id);

/// 一组 iconKey 里所有合法的自定义图片 id。
///
/// 「哪些图标文件还有人用」这个问题在三个地方要问（编辑面板收尾清理、
/// 导入配置后清理、导出备份时决定打包哪些文件），收成一个函数免得
/// 三处各写一遍 `custom:` 前缀的解析。
Set<String> customIconIdsOf(Iterable<String> iconKeys) => {
  for (final key in iconKeys)
    if (customCategoryIconId(key) case final id? when isValidCustomIconId(id))
      id,
};

/// 图标选择器的一个分组：标题 + 该组的 key。
typedef CategoryIconGroup = ({String label, List<String> keys});

/// 图标选择器的内容。**这是「能挑哪些图标」的唯一真相源。**
///
/// ## 为什么不直接铺 lucide 全量
///
/// lucide 有 1900+ 个图标，绝大多数（箭头、代码符号、UI 控件…）和记账毫无
/// 关系。铺全量等于把「找图标」变成一次翻词典，用户根本挑不动。
///
/// ## 也不能直接铺 [categoryIcons] 的 keys
///
/// 那张表是给内置 44 个分类配的，且含同图别名 —— 铺出来会出现十几对
/// 一模一样的格子（`meal`/`restaurant` 同餐具、`travel`/`flight` 同飞机）。
/// 用户看到的是图形，不是 key，重复格子就是纯粹的噪音。
///
/// ## 三条筛选原则
///
/// 1. **覆盖优先于精简**：目标是「用户想得到的分类，八成能找到贴切图标」。
///    宁可多留几个近似的，也不要逼三个分类共用一个图标 —— 记账页的分类
///    选择器全靠图形区分，同图就等于失去区分度。
/// 2. **按图形去重，不按语义去重**：同一个图形只出现一次，取语义最通用的
///    那个 key（如 droplet 归 `water` 而非 `water_bill`）。由
///    `test/category_management_test.dart` 断言唯一性。
/// 3. **必须落在某个分组里**：无组可归的图标说明它不属于记账语境，直接不收。
///
/// ## 分组即导航
///
/// 120 个格子无序平铺就是图标海。分组标题在选择器里粘性吸顶，
/// 用户扫的是「吃喝 / 出行 / 居家…」这七八个词，而不是一百多个图形。
const categoryIconGroups = <CategoryIconGroup>[
  (
    label: '吃喝',
    keys: [
      'restaurant',
      'takeout',
      'fine_dining',
      'beer',
      'drink',
      'milk_tea',
      'milk',
      'water',
      'fruit',
      'vegetable',
      'snack',
      'candy',
      'cake',
      'ice_cream',
      'popcorn',
      'delivery',
    ],
  ),
  (
    label: '购物',
    keys: [
      'shopping',
      'supermarket',
      'store',
      'clothes',
      'shoes',
      'bag',
      'glasses',
      'watch',
      'jewelry',
      'beauty',
      'haircut',
      'digital',
      'laptop',
      'household',
    ],
  ),
  (
    label: '出行',
    keys: [
      'transport',
      'subway',
      'train',
      'taxi',
      'car',
      'fuel',
      'parking',
      'toll',
      'bike',
      'flight',
      'ship',
      'trip',
      'hotel',
      'ticket',
    ],
  ),
  (
    label: '居家',
    keys: [
      'home',
      'rent',
      'property',
      'utilities',
      'electricity',
      'gas',
      'heating',
      'network',
      'phone_bill',
      'furniture',
      'appliance',
      'fridge',
      'tv',
      'lamp',
      'cleaning',
      'renovation',
      'tools',
    ],
  ),
  (
    label: '娱乐',
    keys: [
      'fun',
      'movie',
      'music',
      'theater',
      'sport',
      'swim',
      'ball',
      'camera',
      'art',
      'camping',
      'party',
      'puzzle',
      'toy',
    ],
  ),
  (
    label: '健康',
    keys: [
      'medical',
      'medicine',
      'clinic',
      'injection',
      'bandage',
      'checkup',
      'insurance',
    ],
  ),
  (
    label: '学习',
    keys: ['study', 'course', 'book', 'library', 'stationery', 'language'],
  ),
  (
    label: '家人宠物',
    keys: [
      'gift',
      'favor',
      'parents',
      'family',
      'baby',
      'pet',
      'pet_food',
      'dog',
      'cat',
      'fish',
      'flower',
      'plant',
    ],
  ),
  (
    label: '收支',
    keys: [
      'salary',
      'part_time',
      'finance',
      'living_expense',
      'allowance',
      'family_income',
      'savings',
      'coins',
      'transfer',
      'repayment',
      'refund',
      'invoice',
      'tax',
      'subscription',
      'discount',
      'membership',
    ],
  ),
  (label: '其他', keys: ['other', 'umbrella', 'idea', 'recycle']),
];

/// 全部可选 key 的扁平列表（保持分组顺序）。
///
/// 分组是给界面导航用的；需要「所有可选 key」的地方（校验、测试）用这个。
final categoryIconChoices = <String>[
  for (final group in categoryIconGroups) ...group.keys,
];
