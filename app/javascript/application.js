// app/javascript/application.js
// Import directly from react and react-dom
import * as React from 'react';
import * as ReactDOM from 'react-dom/client';
import Button from './components/Button';

// Make React globally available
window.React = React;

// Wait for the DOM to be fully loaded
document.addEventListener('DOMContentLoaded', () => {
  // Find all react component placeholders
  document.querySelectorAll('[data-react-class]').forEach(el => {
    const componentName = el.getAttribute('data-react-class');
    const propsJSON = el.getAttribute('data-react-props');
    const props = propsJSON ? JSON.parse(propsJSON) : {};
    
    // Currently only supports Button component
    if (componentName === 'Button') {
      const root = ReactDOM.createRoot(el);
      root.render(React.createElement(Button, props));
    }
  });
});