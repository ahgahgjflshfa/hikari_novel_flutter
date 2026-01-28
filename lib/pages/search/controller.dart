import 'package:easy_refresh/easy_refresh.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:hikari_novel_flutter/models/novel_cover.dart';
import 'package:hikari_novel_flutter/models/page_state.dart';
import 'package:hikari_novel_flutter/models/resource.dart';
import 'package:hikari_novel_flutter/network/parser.dart';

import '../../common/database/database.dart';
import '../../network/api.dart';
import '../../service/db_service.dart';

class SearchController extends GetxController {
  SearchController({required this.author});

  final String? author;

  final keywordController = TextEditingController();

  RxInt searchMode = 0.obs;
  RxList<String> searchHistory = RxList();

  Rx<PageState> pageState = Rx(PageState.pleaseSelect);

  String errorMsg = "";

  int _maxNum = 1;
  int _index = 0;
  final RxList<NovelCover> data = RxList();

  @override
  void onReady() {
    super.onReady();

    DBService.instance.getAllSearchHistory().listen((sh) {
      searchHistory.assignAll(sh.reversed.map((e) => e.keyword));
    });

    checkIsAuthorSearch(author);
  }

  void checkIsAuthorSearch(String? author) {
    if (author != null) {
      keywordController.text = author;
      searchMode.value = 1;
      getPage(false);
    }
  }

  /// 点击“搜索历史”后直接触发搜索
  void searchFromHistory(String keyword) {
    keywordController.text = keyword;
    keywordController.selection = TextSelection.fromPosition(
      TextPosition(offset: keywordController.text.length),
    );
    // 直接执行搜索
    getPage(false);
    // 顺便收起键盘
    Get.focusScope?.unfocus();
  }

  Future<IndicatorResult> getPage(bool loadMore) async {
    if (!loadMore) pageState.value = PageState.loading;

    if (!loadMore) {
      DBService.instance.upsertSearchHistory(SearchHistoryEntityData(keyword: keywordController.text));

      data.clear();
      _index = 0;
    }
    if (_index >= _maxNum) {
      return IndicatorResult.noMore;
    }
    _index += 1;

    Resource result;
    if (searchMode.value == 0) {
      result = await Api.searchNovelByTitle(title: keywordController.text, index: _index);
    } else {
      result = await Api.searchNovelByAuthor(author: keywordController.text, index: _index);
    }

    switch (result) {
      case Success():
        {
          final html = result.data;
          if (Parser.isError(html)) {
            if (!loadMore) {
              pageState.value = PageState.inFiveSecond;
            } else {
              Get.dialog(
                AlertDialog(
                  title: Text("warning".tr),
                  content: Text("search_too_quickly_tip".tr),
                  actions: [TextButton(onPressed: Get.back, child: Text("confirm".tr))],
                ),
              );
            }

            return IndicatorResult.fail;
          }

          // 站点在“只有 1 条搜索结果”时会返回一个特殊页面。
          // 以前这里会自动跳转到详情页，但体验上会让用户
          // （尤其是从“搜索历史”点进来时）无法先看到结果列表。
          // 现在统一改为：即使只有 1 本，也先展示搜索结果列表，
          // 让用户自己点一下再进入详情。
          var tempResult = Parser.isSearchResultOnlyOne(html);
          if (tempResult != null) {
            data.add(tempResult);
            _maxNum = 1;
            if (!loadMore) pageState.value = PageState.success;
            return IndicatorResult.noMore;
          }
          if (!loadMore) _maxNum = Parser.getMaxNum(html);

          final parsedHtml = Parser.parseToList(html);

          if (parsedHtml.isEmpty) {
            pageState.value = PageState.empty;
            return IndicatorResult.noMore;
          }

          data.addAll(parsedHtml);
          if (!loadMore) pageState.value = PageState.success;
          return IndicatorResult.success;
        }
      case Error():
        {
          if (!loadMore) {
            errorMsg = result.error;
            pageState.value = PageState.error;
          } else {
            Get.dialog(
              AlertDialog(
                title: Text("error".tr),
                content: Text(result.error.toString()),
                actions: [TextButton(onPressed: () => Get.back(), child: Text("confirm".tr))],
              ),
            );
          }
          if (_index > 0) {
            _index -= 1;
          }
          return IndicatorResult.fail;
        }
    }
  }
}
