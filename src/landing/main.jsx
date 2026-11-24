import React from 'react';
import { createRoot } from 'react-dom/client';
import { Landing } from './Landing.jsx';

document.documentElement.classList.add('has-reveal');

createRoot(document.getElementById('root')).render(<Landing />);
