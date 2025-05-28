// https://vitepress.dev/reference/site-config
export default {
  // app level config options
  lang: 'en-US',
  title: 'Glue',
  base: "/glue/",
  description: 'Lightweight provider system.',

  themeConfig: {
    logo: '/logo.png',

    nav: [
      { text: 'Reference', link: '/reference/api/' },
      { text: 'Changelog', link: 'https://github.com/...' }
    ],

    sidebar: {
      '/guide/': { base: '/guide/', items: sidebarGuide() },
      '/reference/': { base: '/reference/', items: sidebarReference() }  
    },

    // sidebar: [
    //   {
    //     text: 'Introduction',
    //     collapsable: true,
    //     items: [
    //       { text: "What is Glue?" }
  
    //     ]
    //   },
    //   {
    //     text: "Guide",
    //     items: [
    //       { text: "Introduction", link: "guide/index.md" },
    //       { text: "Hooks" },
    //       { text: "Dynamic Units" },
    //       { text: "Dependency Injection" },
    //       { text: "Debugging" },
    //     ]
    //   }
    // ]
  }
}

function sidebarGuide() {
  return [
    {
      text: 'Introduction',
      collapsed: false,
      items: [
        { text: 'What is Glue?', link: 'what-is-glue' },
        { text: 'Getting Started', link: 'getting-started' },
        { text: 'Bootstrap', link: 'bootstrap' },
      ]
    },
    {
      text: 'Units',
      collapsed: false,
      items: [
        { text: 'Static Units', link: 'static-units' },
        { text: 'Lifecycle & Hooks', link: 'lifecycle-hooks' },
        { text: 'Dependencies', link: 'dependencies' },
        { text: 'Dynamic Units', link: 'dynamic-units' }
      ]
    }
  ]
}

function sidebarReference() {
  return [
    {
      text: 'Reference',
      items: [
        { text: 'API Reference', link: 'api' },
        { text: "glue-debug", link: 'glue-debug'}
      ]
    }
  ]
}