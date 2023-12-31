<!--
  This source file is part of the Swift.org open source project

  Copyright (c) 2021 Apple Inc. and the Swift project authors
  Licensed under Apache License v2.0 with Runtime Library Exception

  See https://swift.org/LICENSE.txt for license information
  See https://swift.org/CONTRIBUTORS.txt for Swift project authors
-->

<template>
  <OnThisPageSection
    anchor="parameters"
    class="parameters"
    title="Parameters"
  >
    <h2>Parameters</h2>
    <dl>
      <template v-for="param in parameters">
        <dt class="param-name" :key="`${param.name}:name`">
          <code>{{param.name}}</code>
        </dt>
        <dd class="param-content" :key="`${param.name}:content`">
          <ContentNode :content="param.content" />
        </dd>
      </template>
    </dl>
  </OnThisPageSection>
</template>

<script>
import ContentNode from 'docc-render/components/DocumentationTopic/ContentNode.vue';
import OnThisPageSection from 'docc-render/components/DocumentationTopic/OnThisPageSection.vue';

export default {
  name: 'Parameters',
  components: {
    ContentNode,
    OnThisPageSection,
  },
  props: {
    parameters: {
      type: Array,
      required: true,
    },
  },
};
</script>

<style scoped lang="scss">
@import 'docc-render/styles/_core.scss';

$param-spacing: rem(28px);

.param-name {
  font-weight: $font-weight-semibold;
  padding-left: 1rem;
  padding-top: $param-spacing;

  &:first-child {
    padding-top: 0;
  }

  @include breakpoint(small) {
    padding-left: 0;
  }
}

.param-content {
  padding-left: 2rem;

  @include breakpoint(small) {
    padding-left: 0;
  }

  /deep/ dt {
    font-weight: $font-weight-semibold;
  }

  /deep/ dd {
    margin-left: 1em;
  }
}
</style>
