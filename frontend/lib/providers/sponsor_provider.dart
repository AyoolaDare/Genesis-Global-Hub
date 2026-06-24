import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/api/api_client.dart';
import '../core/api/api_endpoints.dart';

class Sponsor {
  final String id;
  final String name;
  final String? email;
  final String? phone;
  final String? address;
  final String? category;
  final double totalContributions;
  final DateTime createdAt;
  final List<Payment> payments;

  const Sponsor({
    required this.id,
    required this.name,
    this.email,
    this.phone,
    this.address,
    this.category,
    this.totalContributions = 0,
    required this.createdAt,
    this.payments = const [],
  });

  factory Sponsor.fromJson(Map<String, dynamic> json) {
    return Sponsor(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      email: json['email'],
      phone: json['phone'],
      address: json['address'],
      category: json['category'],
      totalContributions:
          (json['total_contributions'] ?? 0.0).toDouble(),
      createdAt: DateTime.parse(
          json['created_at'] ?? DateTime.now().toIso8601String()),
      payments: json['payments'] != null
          ? (json['payments'] as List)
              .map((e) => Payment.fromJson(e))
              .toList()
          : [],
    );
  }
}

class Payment {
  final String id;
  final String sponsorId;
  final String? sponsorName;
  final double amount;
  final DateTime paymentDate;
  final String? purpose;
  final String? reference;
  final String method;

  const Payment({
    required this.id,
    required this.sponsorId,
    this.sponsorName,
    required this.amount,
    required this.paymentDate,
    this.purpose,
    this.reference,
    required this.method,
  });

  factory Payment.fromJson(Map<String, dynamic> json) {
    return Payment(
      id: json['id'] ?? '',
      sponsorId: json['sponsor_id'] ?? '',
      sponsorName: json['sponsor_name'],
      amount: (json['amount'] ?? 0.0).toDouble(),
      paymentDate: DateTime.parse(
          json['payment_date'] ?? DateTime.now().toIso8601String()),
      purpose: json['purpose'],
      reference: json['reference'],
      method: json['method'] ?? 'CASH',
    );
  }
}

class SponsorsList {
  final List<Sponsor> items;
  final int total;
  final int page;
  final int totalPages;

  const SponsorsList({
    required this.items,
    required this.total,
    required this.page,
    required this.totalPages,
  });

  factory SponsorsList.empty() => const SponsorsList(
        items: [],
        total: 0,
        page: 1,
        totalPages: 0,
      );
}

class SponsorNotifier extends AsyncNotifier<SponsorsList> {
  @override
  Future<SponsorsList> build() => fetchSponsors();

  Future<SponsorsList> fetchSponsors({int page = 1, String? search}) async {
    final dio = ref.read(dioProvider);
    final response = await dio.get(
      ApiEndpoints.sponsors,
      queryParameters: {
        'page': page,
        'page_size': 20,
        if (search != null && search.isNotEmpty) 'search': search,
      },
    );
    final data = response.data['data'] as List;
    final meta = response.data['meta'];
    return SponsorsList(
      items: data.map((e) => Sponsor.fromJson(e)).toList(),
      total: meta['total'] ?? 0,
      page: meta['page'] ?? 1,
      totalPages: meta['total_pages'] ?? 1,
    );
  }

  Future<void> refresh({int page = 1, String? search}) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
        () => fetchSponsors(page: page, search: search));
  }
}

final sponsorProvider =
    AsyncNotifierProvider<SponsorNotifier, SponsorsList>(
  () => SponsorNotifier(),
);

final sponsorDetailProvider =
    FutureProvider.family<Sponsor, String>((ref, id) async {
  final dio = ref.read(dioProvider);
  final response = await dio.get(ApiEndpoints.sponsorById(id));
  return Sponsor.fromJson(response.data['data']);
});

class PaymentsList {
  final List<Payment> items;
  final int total;
  final int page;
  final int totalPages;

  const PaymentsList({
    required this.items,
    required this.total,
    required this.page,
    required this.totalPages,
  });

  factory PaymentsList.fromJson(Map<String, dynamic> json) {
    final items = json['items'] ?? json['data'] ?? [];
    final meta = json['meta'] ?? {};
    return PaymentsList(
      items: (items as List).map((e) => Payment.fromJson(e)).toList(),
      total: meta['total'] ?? items.length,
      page: meta['page'] ?? 1,
      totalPages: meta['total_pages'] ?? 1,
    );
  }
}

final paymentsProvider = FutureProvider<List<Payment>>((ref) async {
  final dio = ref.read(dioProvider);
  final response = await dio.get(ApiEndpoints.payments);
  final data = response.data['data'] as List;
  return data.map((e) => Payment.fromJson(e)).toList();
});
