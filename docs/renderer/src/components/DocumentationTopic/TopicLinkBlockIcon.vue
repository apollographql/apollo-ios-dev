<!--
  This source file is part of the Swift.org open source project

  Copyright (c) 2021 Apple Inc. and the Swift project authors
  Licensed under Apache License v2.0 with Runtime Library Exception

  See https://swift.org/LICENSE.txt for license information
  See https://swift.org/CONTRIBUTORS.txt for Swift project authors
-->

<template>
  <div class="topic-icon-wrapper" v-if="icon">
    <component :is="icon" class="topic-icon" />
  </div>
</template>

<script>
import ArticleIcon from 'theme/components/Icons/ArticleIcon.vue';
import CurlyBracketsIcon from 'theme/components/Icons/CurlyBracketsIcon.vue';
import ApiCollectionIcon from 'theme/components/Icons/APIReferenceIcon.vue';
import EndpointIcon from 'theme/components/Icons/EndpointIcon.vue';
import PathIcon from 'theme/components/Icons/PathIcon.vue';
import TutorialIcon from 'theme/components/Icons/TutorialIcon.vue';
import { TopicRole } from 'docc-render/constants/roles';

const TopicRoleIcons = {
  [TopicRole.article]: ArticleIcon,
  [TopicRole.collectionGroup]: ApiCollectionIcon,
  [TopicRole.learn]: PathIcon,
  [TopicRole.overview]: PathIcon,
  [TopicRole.project]: TutorialIcon,
  [TopicRole.tutorial]: TutorialIcon,
  [TopicRole.resources]: PathIcon,
  [TopicRole.sampleCode]: CurlyBracketsIcon,
  [TopicRole.restRequestSymbol]: EndpointIcon,
};

export default {
  props: {
    role: {
      type: String,
      required: true,
    },
  },

  computed: {
    icon: ({ role }) => TopicRoleIcons[role],
  },
};
</script>

<style lang="scss" scoped>
@import 'docc-render/styles/_core.scss';

.topic-icon-wrapper {
  display: flex;
  align-items: center;
  justify-content: center;
  // ensure the wrapper is as tall as the text next to it, so it vert. aligns with the text
  height: rem(25px);
  flex: 0 0 $topic-link-icon-width;
  width: $topic-link-icon-width;
  margin-right: $topic-link-icon-spacing;
}

.topic-icon {
  height: rem(15px);
  @include prevent-clipped-svg();

  // overwrite the height so the icon looks the same size as the rest.
  &.curly-brackets-icon {
    height: rem(17px);
  }
}
</style>
